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
It is expected that the route returns a valid C<Response>, in this case C<.html> returns
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

use v6;
use strict;

use HTTP::Status;
use DateTime::Format::RFC2822;

use Humming-Bird::HTTPServer;

unit module Humming-Bird::Core;

our constant $VERSION = '1.0.0';

### UTILITIES
sub trim-utc-for-gmt(Str $utc --> Str) { $utc.subst(/"+0000"/, 'GMT') }
sub now-rfc2822(--> Str) {
    trim-utc-for-gmt: DateTime.now(formatter => DateTime::Format::RFC2822.new()).utc.Str;
}

### REQUEST/RESPONSE SECTION
enum HTTPMethod is export <GET POST PUT PATCH DELETE HEAD>;

# Convert a string to HTTP method, defaults to GET
sub http_method_of_str(Str $method --> HTTPMethod) {
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
sub decode_headers(Str $header_block --> Map) {
    Map.new($header_block.lines.map({ .split(": ", :skip-empty) }).flat);
}

class Cookie is export {
    has Str $.name;
    has Str $.value;
    has DateTime $.expires;
    has Str $.domain where { .starts-with('/') orelse .throw } = '/';
    has Str $.same-site where { $^a eq 'Strict' | 'Lax' } = 'Strict';
    has Bool $.http-only = True;
    has Bool $.secure = False;

    method decode(--> Str) {
        my $expires = ~trim-utc-for-gmt($.expires.clone(formatter => DateTime::Format::RFC2822.new()).utc.Str);
        ("$.name=$.value", "Expires=$expires", "SameSite=$.same-site", "Domain=$.domain", $.http-only ?? 'HttpOnly' !! '', $.secure ?? 'Secure' !! '')
        .grep({ .chars })
        .join(';');
    }

    submethod encode(Str $cookie-string) {
        Map.new: $cookie-string.split(/\s/, :skip-empty).map(*.split('=', :skip-empty)).flat;
    }
}

class HTTPAction {
    has %.headers is Hash;
    has %.cookies is Hash;
    has Str $.body is rw = "";

    # Find a header in the action, return (Any) if not found
    method header(Str $name --> Str) {
        return Nil without %.headers{$name};
        %.headers{$name};
    }

    method cookie(Str $name) {
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

    method param(Str $param --> Str) {
        return Nil without %.params{$param};
        %.params{$param};
    }

    method query(Str $query_param --> Str) {
        return Nil without %.query{$query_param};
        %.query{$query_param};
    }

    submethod encode(Str $raw_request --> Request) {
        # TODO: Get a better appromixmation or find smallest possible HTTP request size and short circuit if it's smaller
        # Example: GET /hello.html HTTP/1.1\r\n ~~~ Followed my some headers
        my @lines = $raw_request.lines;
        my ($method_raw, $path, $version) = @lines.head.split(' ');

        my $method = http_method_of_str($method_raw);

        # Find query params
        my %query is Hash;
        if @lines[0] ~~ m:g/<[a..z A..Z 0..9]>+"="<[a..z A..Z 0..9]>+/ {
            %query = Map.new($<>.map({ .split('=') }).flat);
            $path = $path.split('?', :skip-empty)[0];
        }

        # Break the request into the body portion, and the upper headers/request line portion
        my @split_request = $raw_request.split("\r\n\r\n", :skip-empty);
        my $body = "";

        # Lose the request line and parse an assoc list of headers.
        my %headers = Map.new(@split_request[0].split("\r\n").tail(*-1).map(*.split(': ', :skip-empty)).flat);

        # Body should only exist if either of these headers are present.
        with %headers<Content-Length> || %headers<Transfer-Encoding> {
            $body = @split_request[1] || $body;
        }

        # Handle absolute URI's
        without %headers<Host> {
            # TODO: Assign the Host header, and make the path relative rather than absolute
            say 'Encountered an absolute URI, this is not implemented yet!';
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
    multi method cookie(Str $name, Cookie $value) {
        %.cookies{$name} = $value;
        $value;
    }
    multi method cookie(Str $name, Str $value, DateTime $expires) {
        # Default
        my $cookie = Cookie.new(:$name, :$value, :$expires);
        %.cookies{$name} = $cookie;
        $cookie;
    }

    method status(Int $status --> Response) {
        $!status = HTTP::Status($status);
        self;
    }

    method html(Str $body --> Response) {
        $.write($body, 'text/html');
    }

    # Write a JSON string to the body of the request
    method json(Str $body --> Response) {
        $.write($body, 'application/json');
    }

    # Set a file to output.
    method file(Str $file --> Response) {
        $.write($file.IO.slurp || '', 'text/plain'); # TODO: Infer type of output based on file extension
    }

    # Write a string to the body of the response, optionally provide a content type
    method write(Str $body, Str $content_type = 'text/plain', --> Response) {
        $.body = $body;
        %.headers{'Content-Type'} = $content_type;
        self;
    }

    # Set content type of the response
    method content_type(Str $type --> Response) {
        %.headers{'Content-Type'} = $type;
        self;
    }

    # $with_body is for HEAD requests.
    method decode(Bool $with_body = True --> Str) {
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
    has Str $.path;
    has &.callback;
    has @.middlewares is Array; # List of functions that type Request --> Request

    method CALL-ME(Request $req) {
        my $res = Response.new(status => HTTP::Status(200));
        if @!middlewares.elems {
            # Compose the middleware together using partial application
            # Finally, the main callback is added to the end of the chain
            my &composition = @!middlewares.map({ .assuming($req, $res) }).reduce(-> &a, &b { &a(-> { &b }) });
            &composition(&!callback.assuming($req, $res));
        } else {
            # If there is are no middlewares, just process the callback
            &!callback($req, $res);
        }
    }
}

our %ROUTES; # TODO: Should be un-modifiable after listen is called.

sub split_uri(Str $uri --> List) {
    my @uri_parts = $uri.split('/', :skip-empty);
    @uri_parts.prepend('/').List;
}

sub delegate_route(Route $route, HTTPMethod $meth) {
    die 'Route cannot be empty'  if $route.path.chars eq 0;
    die sprintf("Invalid route: %s", $route.path) unless $route.path.contains('/');

    my @uri_parts = split_uri($route.path);

    my %loc := %ROUTES;
    for @uri_parts -> Str $part {
        unless %loc{$part}:exists {
            %loc{$part} = Hash.new;
        }

        %loc := %loc{$part};
    }

    %loc{$meth} := $route;
    $route; # Return the route.
}

# TODO: Implement a way for the user to declare their own error handlers (maybe somekind of after middleware?)
my constant $not_found          = Response.new(status => HTTP::Status(404)).html('404 Not Found');
my constant $method_not_allowed = Response.new(status => HTTP::Status(405)).html('405 Method Not Allowed');
my constant $bad_request        = Response.new(status => HTTP::Status(400)).html('Bad request');

sub dispatch_request(Request $request --> Response) {
    my @uri_parts = split_uri($request.path);
    if (@uri_parts.elems < 1) || (@uri_parts.elems == 1 && @uri_parts[0] ne '/') {
        return $bad_request;
    }

    my %loc := %ROUTES;
    for @uri_parts -> $uri {
        my $possible_param = %loc.keys.first: *.starts-with($PARAM_IDX);

        if (not %loc{$uri}:exists) && (not $possible_param) {
            return $not_found;
        } elsif $possible_param && (not %loc{$uri}:exists) {
            $request.params{$possible_param.match(/<[A..Z a..z 0..9 \- \_]>+/).Str} = $uri;
            %loc := %loc{$possible_param};
        } else {
            %loc := %loc{$uri};
        }
    }

    # For HEAD requests we should return a GET request. The decoder will delete the body
    if $request.method === HEAD {
        if %loc{GET}:exists {
            return %loc{GET}($request);
        } else {
            return $method_not_allowed;
        }
    }

    # If we don't support the request method on this route.
    unless %loc{$request.method}:exists {
        return $method_not_allowed;
    }

    %loc{$request.method}($request);
}

sub get(Str $path, &callback, @middlewares = List.new) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), GET);
}

sub put(Str $path, &callback, @middlewares = List.new) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), PUT);
}

sub post(Str $path, &callback, @middlewares = List.new) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), POST);
}

sub patch(Str $path, &callback, @middlewares = List.new) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), PATCH);
}

sub delete(Str $path, &callback, @middlewares = List.new) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), DELETE);
}

sub group(@routes, @middlewares) is export {
    .(@middlewares) for @routes;
}

sub routes(--> Hash) is export {
    %ROUTES.clone;
}

sub listen(Int $port) is export {
    my HTTPServer $server = HTTPServer.new(port => $port);
    $server.listen(-> $raw_request {
        start {
            my Request $request = Request.encode($raw_request);
            my Bool $keep_alive = False;
            with $request.headers<Connection> {
                $keep_alive = True if $request.headers<Connection>.lc eq 'keep-alive';
            }
            # If the request is HEAD, we shouldn't return the body
            my Bool $should_show_body = not ($request.method === HEAD);
            # We need $should_show_body because the Content-Length header should remain on a HEAD request.
            List.new(dispatch_request($request).decode($should_show_body), $keep_alive);
        }
    });
}

# vim: expandtab shiftwidth=4
