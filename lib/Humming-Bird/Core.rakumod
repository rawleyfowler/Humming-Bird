use v6.d;
use strict;

use HTTP::Status;
use DateTime::Format::RFC2822;
use MIME::Types;

use Humming-Bird::HTTPServer;

unit module Humming-Bird::Core;

our constant $VERSION = '2.1.5';

# Mime type parser from MIME::Types
my constant $mime = MIME::Types.new;

### UTILITIES
sub trim-utc-for-gmt(Str:D $utc --> Str:D) { $utc.subst(/"+0000"/, 'GMT') }
sub now-rfc2822(--> Str:D) {
    trim-utc-for-gmt: DateTime.now(formatter => DateTime::Format::RFC2822.new()).utc.Str;
}

### REQUEST/RESPONSE SECTION
enum HTTPMethod is export <GET POST PUT PATCH DELETE HEAD>;

# Convert a string to HTTP method, defaults to GET
sub http-method-of-str(Str:D $method --> HTTPMethod:D) {
    given $method.lc {
        when 'get' { GET }
        when 'post' { POST; }
        when 'put' { PUT }
        when 'patch' { PATCH }
        when 'delete' { DELETE }
        when 'head' { HEAD }
        default { GET }
    }
}

# Converts a string of headers "KEY: VALUE\r\nKEY: VALUE\r\n..." to a map of headers.
sub decode_headers(Str:D $header_block --> Map:D) {
    Map.new($header_block.lines.map({ .split(": ", :skip-empty) }).flat);
}

subset SameSite of Str where 'Strict' | 'Lax';
class Cookie is export {
    has Str $.name;
    has Str $.value;
    has DateTime $.expires;
    has Str $.domain;
    has Str $.path where { .starts-with('/') orelse .throw } = '/';
    has SameSite $.same-site = 'Strict';
    has Bool $.http-only = True;
    has Bool $.secure = False;

    method encode(--> Str:D) {
        my $expires = ~trim-utc-for-gmt($.expires.clone(formatter => DateTime::Format::RFC2822.new()).utc.Str);
        ("$.name=$.value", "Expires=$expires", "SameSite=$.same-site", "Path=$.path", $.http-only ?? 'HttpOnly' !! '', $.secure ?? 'Secure' !! '', $.domain // '')
        .grep({ .chars })
        .join('; ');
    }

    submethod decode(Str:D $cookie-string) { # We decode "simple" cookies only, since they come from the requests
        Map.new: $cookie-string.split(/\s/, 2, :skip-empty)
                  .map(*.split('=', 2, :skip-empty))
                  .map(-> ($name, $value) { $name => Cookie.new(:$name, :$value) })
                  .flat;
    }
}

my subset Body where * ~~ Buf:D | Str:D;
class HTTPAction {
    has $.context-id;
    has %.headers;
    has %.cookies;
    has %.stash; # The stash is never encoded or decoded. It exists purely for internal talking between middlewares, request handlers, etc.
    has Body:D $.body is rw = "";

    # Find a header in the action, return (Any) if not found
    multi method header(Str:D $name --> Str) {
        return Nil without %.headers{$name};
        %.headers{$name};
    }

    multi method header(Str:D $name, Str:D $value --> HTTPAction:D) {
        %.headers{$name} = $value;
        self;
    }

    multi method cookie(Str:D $name --> Cookie) {
        return Nil without %.cookies{$name};
        %.cookies{$name};
    }

    method log(Str:D $message, :$file = $*OUT) {
        $file.print: "[Context: { self.context-id }] | [Time: { DateTime.now }] | $message\n";
        self;
    }
}

my sub parse-urlencoded(Str:D $urlencoded --> Map:D) {
    use URI::Encode;
    uri_decode_component($urlencoded).split('&', :skip-empty)>>.split('=', :skip-empty)>>.map(-> $a, $b { $b.contains(',') ?? slip $a => $b.split(',', :skip-empty) !! slip $a => $b }).flat.Map;
}

class Request is HTTPAction is export {
    has Str $.path is required;
    has HTTPMethod $.method is required;
    has Str $.version is required;
    has %.params;
    has %.query;
    has $!content;

    # Attempts to parse the body to a Map or return an empty map if we can't decode it
    method content(--> Map:D) {
        use JSON::Fast;

        state $prev-body = $.body;
        
        return $!content if $!content && ($prev-body eqv $.body);
        return $!content = Map.new unless self.header('Content-Type');

        try {
            CATCH { default { warn "Failed trying to parse a body of type { self.header('Content-Type') }"; return ($!content = Map.new) } }
            if self.header('Content-Type').ends-with: 'json' {
                $!content = from-json(self.body).Map;
            } elsif self.header('Content-Type').ends-with: 'urlencoded' {
                $!content = parse-urlencoded(self.body);
            }

            return $!content;
        }

        $!content = Map.new;
    }

    method param(Str:D $param --> Str) {
        return Nil without %!params{$param};
        %!params{$param};
    }

    method queries {
        return %!query;
    }

    multi method query {
        return %!query;
    }
    multi method query(Str:D $query_param --> Str) {
        return Nil without %!query{$query_param};
        %!query{$query_param};
    }

    submethod decode(Str:D $raw-request --> Request:D) {
        use URI::Encode;
        # Example: GET /hello.html HTTP/1.1\r\n ~~~ Followed my some headers
        my @lines = $raw-request.lines;
        my ($method_raw, $path, $version) = @lines.head.split(/\s/, :skip-empty);

        my $method = http-method-of-str($method_raw);

        # Find query params
        my %query;
        if uri_decode_component($path) ~~ m:g /\w+"="(<-[&]>+)/ {
            %query = Map.new($<>.map({ .split('=', 2) }).flat);
            $path = $path.split('?', 2)[0];
        }

        # Break the request into the body portion, and the upper headers/request line portion
        my @split_request = $raw-request.split("\r\n\r\n", 2, :skip-empty);
        my $body = "";

        # Lose the request line and parse an assoc list of headers.
        my %headers = Map.new(|@split_request[0].split("\r\n", :skip-empty).tail(*-1).map(*.split(':', 2).map(*.trim)).flat);

        # Body should only exist if either of these headers are present.
        with %headers<Content-Length> || %headers<Transfer-Encoding> {
            $body = @split_request[1] || $body;
        }

        # Absolute uris need their path encoded differently.
        without %headers<Host> {
            my $abs-uri = $path;
            $path = $abs-uri.match(/^'http' 's'? '://' <[A..Z a..z \w \. \- \_ 0..9]>+ <('/'.*)>? $/).Str;
            %headers<Host> = $abs-uri.match(/^'http''s'?'://'(<-[/]>+)'/'?.* $/)[0].Str;
        }

        my %cookies;
        # Parse cookies
        with %headers<Cookie> {
            %cookies := Cookie.decode(%headers<Cookie>);
        }

        my $context-id = rand.Str.subst('0.', '').substr: 0, 5;

        Request.new(:$path, :$method, :$version, :%query, :$body, :%headers, :%cookies, :$context-id);
    }
}

class Response is HTTPAction is export {
    has HTTP::Status $.status is required;
    has Request:D $.initiator is required handles <context-id>;

    proto method cookie(|) {*}
    multi method cookie(Str:D $name, Cookie:D $value) {
        %.cookies{$name} = $value;
        self;
    }
    multi method cookie(Str:D $name, Str:D $value, DateTime:D $expires) {
        # Default
        my $cookie = Cookie.new(:$name, :$value, :$expires);
        %.cookies{$name} = $cookie;
        self;
    }
    multi method cookie(Str:D $name, Str:D $value, :$expires, :$secure) {
        my $cookie = Cookie.new(:$name, :$value, :$expires, :$secure);
        %.cookies{$name} = $cookie;
        self;        
    }

    proto method status(|) {*}
    multi method status(--> HTTP::Status) { $!status }
    multi method status(Int:D $status --> Response:D) {
        $!status = HTTP::Status($status);
        self;
    }
    multi method status(HTTP::Status:D $status --> Response:D) {
        $!status = $status;
        self;
    }

    # Redirect to a given URI, :$permanent allows for a 308 status code vs a 307
    method redirect(Str:D $to, :$permanent, :$temporary) {
        %.headers<Location> = $to;
        self.status(303);

        self.status(307) if $temporary;
        self.status(308) if $permanent;
        
        self;
    }

    method html(Str:D $body --> Response:D) {
        $.write($body, 'text/html');
        self;
    }

    # Write a JSON string to the body of the request
    method json(Str:D $body --> Response:D) {
        $.write($body, 'application/json');
        self;
    }

    # Set a file to output.
    method file(Str:D $file --> Response:D) {
        my $text = $file.IO.slurp(:bin);
        my $mime-type = $mime.type($file.IO.extension) // 'text/plain';
        try {
            CATCH {
                $mime-type = 'application/octet-stream' if $mime-type eq 'text/plain';
                return $.blob($text, $mime-type);
            }
            # Decode will fail if it's a binary file
            $.write($text.decode, $mime-type);
        }
        self;
    }

    # Write a blob or buffer
    method blob(Buf:D $body, Str:D $content-type = 'application/octet-stream', --> Response:D) {
        $.body = $body;
        %.headers<Content-Type> = $content-type;
        self;
    }
    # Alias for blob
    multi method write(Buf:D $body, Str:D $content-type = 'application/octet-stream', --> Response:D) {
        self.blob($body, $content-type);
    }
    # Write a string to the body of the response, optionally provide a content type
    multi method write(Str:D $body, Str:D $content-type = 'text/plain', --> Response:D) {
        $.body = $body;
        %.headers<Content-Type> = $content-type;
        self;
    }
    multi method write(Failure $body, Str:D $content-type = 'text/plain', --> Response:D) {
        self.write($body.Str ~ "\n" ~ $body.backtrace, $content-type);
        self.status(500);
        self;
    }

    # Set content type of the response
    method content-type(Str:D $type --> Response) {
        %.headers<Content-Type> = $type;
        self;
    }

    # $with_body is for HEAD requests.
    method encode(Bool:D $with-body = True --> Buf:D) {
        my $out = sprintf("HTTP/1.1 %d $!status\r\n", $!status.code);
        my $body-size = $.body ~~ Buf:D ?? $.body.bytes !! $.body.chars;

        if $body-size > 0 && %.headers<Content-Type> {
            %.headers<Content-Type> ~= '; charset=utf8';
        }

        $out ~= sprintf("Content-Length: %d\r\n", $body-size);
        $out ~= sprintf("Date: %s\r\n", now-rfc2822);
        $out ~= "X-Server: Humming-Bird v$VERSION\r\n";

        for %.headers.pairs {
            $out ~= sprintf("%s: %s\r\n", .key, .value);
        }

        for %.cookies.values {
            $out ~= sprintf("Set-Cookie: %s\r\n", .encode);
        }

        $out ~= "\r\n";

        do given $.body {
            when Str:D {
                my $resp = $out ~ $.body;
                $resp.encode.Buf if $with-body;
            }

            when Buf:D {
                ($out.encode ~ $.body).Buf if $with-body;
            }
        }
    }
}

### ROUTING SECTION
my constant $PARAM_IDX     = ':';
my constant $CATCH_ALL_IDX = '**';

our %ROUTES;
our @MIDDLEWARE;
our @ADVICE = [{ $^a }];
our %ERROR;

class Route {
    has Str:D $.path is required where { ($^a eq '') or $^a.starts-with('/') };
    has Bool:D $.static = False;
    has &.callback is required;
    has @.middlewares; # List of functions that type Request --> Request

    submethod TWEAK {
        @!middlewares.prepend: @MIDDLEWARE;
    }

    method CALL-ME(Request:D $req) {
        my $res = Response.new(initiator => $req, status => HTTP::Status(200));
        if @!middlewares.elems {
            state &composition = @!middlewares.map({ .assuming($req, $res) }).reduce(-> &a, &b { &a({ &b }) });
            # Finally, the main callback is added to the end of the chain
            &composition(&!callback.assuming($req, $res));
        } else {
            # If there is are no middlewares, just process the callback
            &!callback($req, $res);
        }
    }
}

sub split_uri(Str:D $uri --> List:D) {
    my @uri_parts = $uri.split('/', :skip-empty);
    @uri_parts.prepend('/').List;
}

sub delegate-route(Route:D $route, HTTPMethod:D $meth --> Route:D) {
    die 'Route cannot be empty' unless $route.path;
    die "Invalid route: { $route.path }" unless $route.path.contains('/');

    my @uri_parts = split_uri($route.path);

    my %loc := %ROUTES;
    for @uri_parts -> Str:D $part {
        unless %loc{$part}:exists {
            %loc{$part} = Hash.new;
        }

        %loc := %loc{$part};
    }

    %loc{$meth} := $route;
    $route; # Return the route.
}

class Router is export {
    has Str:D $.root is required;
    has @.routes;
    has @!middlewares;
    has @!advice = { $^a }; # List of functions that type Response --> Response

    method !add-route(Route:D $route, HTTPMethod:D $method --> Route:D) {
        my &advice = [o] @!advice;
        my &cb = $route.callback;
        my $r = $route.clone(path => $!root ~ $route.path,
                             middlewares => [|@!middlewares, |$route.middlewares],
                             callback => { &advice(&cb($^a, $^b)) });
        @!routes.push: $r;
        delegate-route($r, $method);
    }

    multi method get(Str:D $path, &callback, @middlewares = List.new) {
        self!add-route(Route.new(:$path, :&callback, :@middlewares), GET);
    }
    multi method get(&callback, @middlewares = List.new) {
        self.get('', &callback, @middlewares);
    }

    multi method post(Str:D $path, &callback, @middlewares = List.new) {
        self!add-route(Route.new(:$path, :&callback, :@middlewares), POST);
    }
    multi method post(&callback, @middlewares = List.new) {
        self.post('', &callback, @middlewares);
    }

    multi method put(Str:D $path, &callback, @middlewares = List.new) {
        self!add-route(Route.new(:$path, :&callback, :@middlewares), PUT);
    }
    multi method put(&callback, @middlewares = List.new) {
        self.put('', &callback, @middlewares);
    }

    multi method patch(Str:D $path, &callback, @middlewares = List.new) {
        self!add-route(Route.new(:$path, :&callback, :@middlewares), PATCH);
    }
    multi method patch(&callback, @middlewares = List.new) {
        self.patch('', &callback, @middlewares);
    }

    multi method delete(Str:D $path, &callback, @middlewares = List.new) {
        self!add-route(Route.new(:$path, :&callback, :@middlewares), DELETE);
    }
    multi method delete(&callback, @middlewares = List.new) {
        self.delete('', &callback, @middlewares);
    }

    method middleware(&middleware) {
        @!middlewares.push: &middleware;
    }

    method advice(&advice) {
        @!advice.push: &advice;
    }

    method TWEAK {
        $!root = ('/' ~ $!root) unless $!root.starts-with: '/';
    }
}

my sub NOT-FOUND(Request:D $initiator --> Response:D) {
    Response.new(:$initiator, status => HTTP::Status(404)).html('404 Not Found');
}
my sub METHOD-NOT-ALLOWED(Request:D $initiator --> Response:D) {
    Response.new(:$initiator, status => HTTP::Status(405)).html('405 Method Not Allowed');
}
my sub BAD-REQUEST(Request:D $initiator --> Response:D) {
    Response.new(:$initiator, status => HTTP::Status(400)).html('400 Bad request');
}
my sub SERVER-ERROR(Request:D $initiator --> Response:D) {
    Response.new(:$initiator, status => HTTP::Status(500)).html('500 Server Error');
}

sub dispatch-request(Request:D $request --> Response:D) {
    my @uri_parts = split_uri($request.path);
    if (@uri_parts.elems < 1) || (@uri_parts.elems == 1 && @uri_parts[0] ne '/') {
        return BAD-REQUEST($request);
    }

    my %loc := %ROUTES;
    my %catch-all;
    for @uri_parts -> $uri {
        my $possible-param = %loc.keys.first: *.starts-with($PARAM_IDX);
        %catch-all = %loc{$CATCH_ALL_IDX} if %loc.keys.first: * eq $CATCH_ALL_IDX;

        if %loc{$uri}:!exists && !$possible-param {
            if %catch-all {
                %loc := %catch-all;
                last;
            }
            
            return NOT-FOUND($request);
        } elsif $possible-param && !%loc{$uri} {
            $request.params{~$possible-param.match(/<[A..Z a..z 0..9 \- \_]>+/)} = $uri;
            %loc := %loc{$possible-param};
        } else {
            %loc := %loc{$uri};
        }

		# If the route could possibly be static
        with %loc{$request.method} {
		    if %loc{$request.method}.static {
			    return %loc{$request.method}($request);
		    }
        }
    }

    # For HEAD requests we should return a GET request. The decoder will delete the body
    if $request.method === HEAD {
        if %loc{GET}:exists {
            return %loc{GET}($request);
        } else {
            return METHOD-NOT-ALLOWED($request);
        }
    }

    # If we don't support the request method on this route.
    without %loc{$request.method} {
        return METHOD-NOT-ALLOWED($request);
    }
    
    try {
        # This is how we pass to error handlers.
        CATCH {
            when %ERROR{.^name}:exists { return %ERROR{.^name}($_, SERVER-ERROR($request)) }
            default {
                my $err = $_;
                with %*ENV<HUMMING_BIRD_ENV> {
                    if .lc ~~ 'prod' | 'production' {
                        return SERVER-ERROR($request);
                    }
                }
                return SERVER-ERROR($request).html("<h1>500 Internal Server Error</h1><br><i> $err <br> { $err.backtrace.nice } </i>");
            }
        }
        
        return %loc{$request.method}($request);
    }
}

sub get(Str:D $path, &callback, @middlewares = List.new) is export {
    delegate-route(Route.new(:$path, :&callback, :@middlewares), GET);
}

sub put(Str:D $path, &callback, @middlewares = List.new) is export {
    delegate-route(Route.new(:$path, :&callback, :@middlewares), PUT);
}

sub post(Str:D $path, &callback, @middlewares = List.new) is export {
    delegate-route(Route.new(:$path, :&callback, :@middlewares), POST);
}

sub patch(Str:D $path, &callback, @middlewares = List.new) is export {
    delegate-route(Route.new(:$path, :&callback, :@middlewares), PATCH);
}

sub delete(Str:D $path, &callback, @middlewares = List.new) is export {
    delegate-route(Route.new(:$path, :&callback, :@middlewares), DELETE);
}

sub group(@routes, @middlewares) is export {
    .(@middlewares) for @routes;
}

multi sub static(Str:D $path, Str:D $static-path, @middlewares = List.new) is export { static($path, $static-path.IO, @middlewares) }
multi sub static(Str:D $path, IO::Path:D $static-path, @middlewares = List.new) is export {
	
	my sub callback(Request:D $request, Response:D $response) {
		return $response.status(400) if $request.path.contains: '..';
		my $cut-size = $path.ends-with('/') ?? $path.chars !! $path.chars + 1;
        my $file = $static-path.add($request.path.substr: $cut-size, $request.path.chars);

        return NOT-FOUND($request) unless $file.e;

		$response.file(~$file);
	}

	delegate-route(Route.new(:$path, :&callback, :@middlewares, :is-static), GET);
}

multi sub advice(--> List:D) is export {
    @ADVICE.clone;
}

multi sub advice(@advice) is export {
    @ADVICE.append: @advice;
}

multi sub advice(&advice) is export {
    @ADVICE.push: &advice;
}

multi sub middleware(@middleware) is export {
    @MIDDLEWARE.append: @middleware;
}

multi sub middleware(&middleware) is export {
    @MIDDLEWARE.push: &middleware;
}

multi sub middleware { return @MIDDLEWARE.clone }

sub error($type, &handler) is export {
    %ERROR{$type.^name} = &handler;
}

sub routes(--> Hash:D) is export {
    %ROUTES.clone;
}

sub handle($raw-request) {
    my Request:D $request = Request.decode($raw-request);
    my Bool:D $keep-alive = False;
    my &advice = [o] @ADVICE; # Advice are Response --> Response

    with $request.headers<Connection> {
        $keep-alive = .lc eq 'keep-alive';
    }

    # If the request is HEAD, we shouldn't return the body
    my Bool:D $should-show-body = !($request.method === HEAD);
    # We need $should_show_body because the Content-Length header should remain on a HEAD request
    return (&advice(dispatch-request($request)).encode($should-show-body), $keep-alive);
}

sub listen(Int:D $port, :$no-block, :$timeout) is export {
    my $timeout-real = $timeout // 3; # Sockets are closed after 3 seconds of inactivity
    my $server = HTTPServer.new(:$port, timeout => $timeout-real);
    if $no-block {
        start {
            $server.listen(&handle);
        }
    } else {
        $server.listen(&handle);
    }
}

=begin pod
=head1 Humming-Bird::Core

A simple imperative web framework. Similar to Opium (OCaml) and Express (JavaScript).
Humming-Bird aims to provide a simple, straight-forward HTTP Application server.
Humming-Bird is not designed to be exposed to the world-wide web without a reverse proxy,
I recommend NGiNX. This is why TLS is not implemented.

=head2 Exported subroutines

=head3 get, post, put, patch, delete

=for code
    get('/home', -> $request, $response {
      $response.html('<h1>Hello World</h1>');
    });

    post('/users', -> $request, $response {
      my $text = sprintf("Hello: %s", $request.body);
      $response.write($text); # Content type defaults to text/plain
    });

    delete ...
    put ...
    patch ...
    head ...

Register an HTTP route, and a C<Block> that takes a Request and a Response.
It is expected that the route handler returns a valid C<Response>, in this case C<.html> returns
the response object for easy chaining. Bodies of requests can be parsed using C<.content> which
will attempt to parse the request based on the content-type, this only supports JSON and urlencoded
requests at the moment.

=head3 group

=for code
    # Add middleware to a few routes
    group([
        &get.assuming('/', -> $request, $response {
            $response.html('Index');
        }),

        &get.assuming('/other', -> $request, $response {
            $response.html('Other');
        })
    ], [ &m_logger, &my_middleware ]);

Group registers multiple routes functionally via partial application. This allows you to
group as many different routes together and feed them a C<List> of middleware in the last parameter.
Group takes a C<List> of route functions partially applied to their route and callback, then a C<List>
of middleware to apply to the routes.

=head3 listen

=for code
    listen(8080);

Start the server, after you've declared your routes. It will listen in a given port.

=head3 routes

=for code
    routes();

Returns a read-only version of the currently stored routes.

=head3 HTTPMethod

Simply an ENUM that contains the major HTTP methods allowed by Humming-Bird.

=end pod

# vim: expandtab shiftwidth=4
