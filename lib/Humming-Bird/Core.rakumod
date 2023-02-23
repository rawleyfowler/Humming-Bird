use v6.d;
use strict;

use HTTP::Status;
use DateTime::Format::RFC2822;
use MIME::Types;

use Humming-Bird::HTTPServer;

unit module Humming-Bird::Core;

our constant $VERSION = '2.0.1';

my constant $mime = MIME::Types.new;

### UTILITIES
sub trim-utc-for-gmt(Str:D $utc --> Str) { $utc.subst(/"+0000"/, 'GMT') }
sub now-rfc2822(--> Str) {
    trim-utc-for-gmt: DateTime.now(formatter => DateTime::Format::RFC2822.new()).utc.Str;
}

### REQUEST/RESPONSE SECTION
enum HTTPMethod is export <GET POST PUT PATCH DELETE HEAD>;

# Convert a string to HTTP method, defaults to GET
sub http_method_of_str(Str:D $method --> HTTPMethod) {
    given $method.lc {
        when 'get' { GET; }
        when 'post' { POST; }
        when 'put' { PUT; }
        when 'patch' { PATCH; }
        when 'delete' { DELETE; }
        when 'head' { HEAD; }
        default { GET; }
    }
}

# Converts a string of headers "KEY: VALUE\r\nKEY: VALUE\r\n..." to a map of headers.
sub decode_headers(Str:D $header_block --> Map) {
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

    method decode(--> Str) {
        my $expires = ~trim-utc-for-gmt($.expires.clone(formatter => DateTime::Format::RFC2822.new()).utc.Str);
        ("$.name=$.value", "Expires=$expires", "SameSite=$.same-site", "Path=$.path", $.http-only ?? 'HttpOnly' !! '', $.secure ?? 'Secure' !! '', $.domain // '')
        .grep({ .chars })
        .join('; ');
    }

    submethod encode(Str:D $cookie-string) { # We encode "simple" cookies only, since they come from the requests
        Map.new: $cookie-string
                    .split(/\s/, :skip-empty)
                    .map(*.split('=', :skip-empty))
                    .map(-> ($name, $value) { $name => Cookie.new(:$name, :$value) })
                    .flat;
    }
}

class HTTPAction {
    has %.headers is Hash;
    has %.cookies is Hash;
    has Str $.body is rw = "";

    # Find a header in the action, return (Any) if not found
    method header(Str:D $name --> Str) {
        return Nil without %.headers{$name};
        %.headers{$name};
    }

    method cookie(Str:D $name) {
        return Nil without %.cookies{$name};
        %.cookies{$name};
    }
}

class Request is HTTPAction is export {
    has Str $.path is required;
    has HTTPMethod $.method is required;
    has Str $.version is required;
    has %.params;
    has %.query;

    method param(Str:D $param --> Str) {
        return Nil without %!params{$param};
        %!params{$param};
    }

    method query(Str:D $query_param --> Str) {
        return Nil without %!query{$query_param};
        %!query{$query_param};
    }

    submethod encode(Str:D $raw-request --> Request) {
        # TODO: Get a better appromixmation or find smallest possible HTTP request size and short circuit if it's smaller
        # Example: GET /hello.html HTTP/1.1\r\n ~~~ Followed my some headers
        my @lines = $raw-request.lines;
        my ($method_raw, $path, $version) = @lines.head.split(' ');

        my $method = http_method_of_str($method_raw);

        # Find query params
        my %query is Hash;
        if @lines[0] ~~ m:g /<[a..z A..Z 0..9]>+"="<[a..z A..Z 0..9]>+/ {
            %query = Map.new($<>.map({ .split('=') }).flat);
            $path = $path.split('?', :skip-empty)[0];
        }

        # Break the request into the body portion, and the upper headers/request line portion
        my @split_request = $raw-request.split("\r\n\r\n", :skip-empty);
        my $body = "";

        # Lose the request line and parse an assoc list of headers.
        my %headers = Map.new(@split_request[0].split("\r\n").tail(*-1).map(*.split(': ', :skip-empty)).flat);

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
            %cookies := Cookie.encode(%headers<Cookie>);
        }

        Request.new(:$path, :$method, :$version, :%query, :$body, :%headers, :%cookies);
    }
}

class Response is HTTPAction is export {
    has HTTP::Status $.status is required;

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

    proto method status(|) {*}
    multi method status(--> HTTP::Status) { $!status }
    multi method status(Int:D $status --> Response) {
        $!status = HTTP::Status($status);
        self;
    }
    multi method status(HTTP::Status:D $status --> Response) {
        $!status = $status;
        self;
    }

    # Redirect to a given URI, :$permanent allows for a 308 status code vs a 307
    method redirect(Str:D $to, :$permanent) {
        %.headers<Location> = $to;
        self.status(307) without $permanent;
        self.status(308) with $permanent;
        self;
    }

    method html(Str:D $body --> Response) {
        $.write($body, 'text/html');
    }

    # Write a JSON string to the body of the request
    method json(Str:D $body --> Response) {
        $.write($body, 'application/json');
    }

    # Set a file to output.
    method file(Str:D $file --> Response) {
        $.write($file.IO.slurp, $mime.type($file.IO.extension) // 'text/plain'); # TODO: Infer type of output based on file extension
    }

    # Write a string to the body of the response, optionally provide a content type
    multi method write(Str:D $body, Str:D $content-type = 'text/plain', --> Response) {
        $.body = $body;
        %.headers{'Content-Type'} = $content-type;
        self;
    }

    multi method write(Failure $body, Str:D $content-type = 'text/plain', --> Response) {
        self.write($body.Str ~ "\n" ~ $body.backtrace, $content-type);
        self.status(500);
        self;
    }

    # Set content type of the response
    method content-type(Str:D $type --> Response) {
        %.headers{'Content-Type'} = $type;
        self;
    }

    # $with_body is for HEAD requests.
    method decode(Bool:D $with_body = True --> Str) {
        my $out = sprintf("HTTP/1.1 %d $!status\r\n", $!status.code);

        $out ~= sprintf("Content-Length: %d\r\n", $.body.chars);
        $out ~= sprintf("Date: %s\r\n", now-rfc2822);
        $out ~= "X-Server: Humming-Bird v$VERSION\r\n";

        for %.headers.pairs {
            $out ~= sprintf("%s: %s\r\n", .key, .value);
        }

        for %.cookies.values {
            $out ~= sprintf("Set-Cookie: %s\r\n", .decode);
        }

        $out ~= "\r\n";
        $out ~= "$.body" if $with_body;

        $out;
    }
}

### ROUTING SECTION
my constant $PARAM_IDX = ':';

class Route is Callable {
    has Str:D $.path is required;
    has &.callback is required;
    has @.middlewares; # List of functions that type Request --> Request
	has Bool:D $.static = False;

    method CALL-ME(Request:D $req) {
        my $res = Response.new(status => HTTP::Status(200));
        if @!middlewares.elems {
            state &composition = @!middlewares.map({ .assuming($req, $res) }).reduce(-> &a, &b { &a(-> { &b }) });
            # Finally, the main callback is added to the end of the chain
            &composition(&!callback.assuming($req, $res));
        } else {
            # If there is are no middlewares, just process the callback
            &!callback($req, $res);
        }
    }
}

our %ROUTES; # TODO: Should be un-modifiable after listen is called.
our @ADVICE = [{ $^a }];
our %ERROR;

sub split_uri(Str:D $uri --> List:D) {
    my @uri_parts = $uri.split('/', :skip-empty);
    @uri_parts.prepend('/').List;
}

sub delegate-route(Route:D $route, HTTPMethod:D $meth) {
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

my constant $NOT-FOUND          = Response.new(status => HTTP::Status(404)).html('404 Not Found');
my constant $METHOD-NOT-ALLOWED = Response.new(status => HTTP::Status(405)).html('405 Method Not Allowed');
my constant $BAD-REQUEST        = Response.new(status => HTTP::Status(400)).html('400 Bad request');
my constant $SERVER-ERROR       = Response.new(status => HTTP::Status(500)).html('500 Server Error');

sub dispatch-request(Request:D $request --> Response:D) {
    my @uri_parts = split_uri($request.path);
    if (@uri_parts.elems < 1) || (@uri_parts.elems == 1 && @uri_parts[0] ne '/') {
        return $BAD-REQUEST;
    }

    my %loc := %ROUTES;
    for @uri_parts -> $uri {
        my $possible-param = %loc.keys.first: *.starts-with($PARAM_IDX);

        if  %loc{$uri}:!exists && !$possible-param {
            return $NOT-FOUND;
        } elsif $possible-param && !%loc{$uri} {
            $request.params{~$possible-param.match(/<[A..Z a..z 0..9 \- \_]>+/)} = $uri;
            %loc := %loc{$possible-param};
        } else {
            %loc := %loc{$uri};
        }

		# If the route could possibly be static
		if %loc{$request.method}.static {
			return %loc{$request.method}($request);
		}
    }

    # For HEAD requests we should return a GET request. The decoder will delete the body
    if $request.method === HEAD {
        if %loc{GET}:exists {
            return %loc{GET}($request);
        } else {
            return $METHOD-NOT-ALLOWED;
        }
    }

    # If we don't support the request method on this route.
    without %loc{$request.method} {
        return $METHOD-NOT-ALLOWED;
    }

    my Response $response;
    try {
        # This is how we pass to error handlers.
        CATCH {
            when %ERROR{.^name}:exists { return %ERROR{.^name}($_) }
            default { return $SERVER-ERROR; }
        }

        $response = %loc{$request.method}($request);
        return $response;
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

        return $NOT-FOUND unless $file.e;

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

sub error($type, &handler) is export {
    %ERROR{$type.^name} = &handler;
}

sub routes(--> Hash:D) is export {
    %ROUTES.clone;
}

sub handle($raw-request) {
    my Request $request = Request.encode($raw-request);
    my Bool $keep-alive = False;
    my &advice = [o] @ADVICE; # Advice are Response --> Response

    with $request.headers<Connection> {
        $keep-alive = $_.lc eq 'keep-alive';
    }

    # If the request is HEAD, we shouldn't return the body
    my Bool $should-show-body = not ($request.method === HEAD);
    # We need $should_show_body because the Content-Length header should remain on a HEAD request
    return (&advice(dispatch-request($request)).decode($should-show-body), $keep-alive);
}

sub listen(Int:D $port, :$no-block) is export {
    my $server = HTTPServer.new(:$port);
    if $no-block {
        do start {
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
the response object for easy chaining. There is no built in body parsers, so you'll have to
convert bodies with another library, JSON::Fast is a good option for JSON!

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
