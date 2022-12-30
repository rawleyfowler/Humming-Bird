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
use Humming-Bird::HTTPServer;

unit module Humming-Bird::Core;

### HTTP REQUEST/RESPONSE SECTION
enum HTTPMethod is export <GET POST PUT PATCH DELETE HEAD>;

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

sub decode_headers(Str $header_block --> Map) {
    Map.new($header_block.lines.map({ .split(": ", :skip-empty) }).flat);
}

our $VERSION = '0.1.0';

class HTTPAction {
    has %.headers is Hash;
    has Str $.body is rw = "";

    method header(Str $name --> Str) {
        if %.headers{$name}:exists {
            return %.headers{$name};
        }

        Nil;
    }
}

class Request is HTTPAction is export {
    has Str $.path is required;
    has HTTPMethod $.method is required;
    has Str $.version is required;
    has %.params;
    has %.query;

    method param(Str $param --> Str) {
        if %!params{$param}:exists {
            return %!params{$param};
        }

        Nil;
    }

    method query(Str $query_param --> Str) {
        if %!query{$query_param}:exists {
            return %!query{$query_param};
        }

        Nil;
    }

    submethod encode(Str $raw_request --> Request) {
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
        if (%headers{'Content-Length'}:exists) || (%headers{'Transfer-Encoding'}:exists) {
            $body = @split_request[1] || "";
        }

        my $request = Request.new(:$path, :$method, :$version, :%query, :$body, :%headers);

        $request;
    }
}

class Response is HTTPAction is export {
    has HTTP::Status $.status is required;

    method status(Int $status --> Response) {
        $!status = HTTP::Status($status);
        self;
    }

    method html(Str $body --> Response) {
        $.write($body, 'text/html');
    }

    method json(Str $body --> Response) {
        $.write($body, 'application/json');
    }

    method write(Str $body, Str $content_type = 'text/plain', --> Response) {
        $.body = $body;
        %.headers{'Content-Type'} = $content_type;
        self;
    }

    method file(Str $file --> Response) {
        $.write($file.IO.slurp || '', 'text/plain');
    }

    method content_type(Str $type --> Response) {
        %.headers{'Content-Type'} = $type;
        self;
    }

    method decode(--> Str) {
        my $out = sprintf("HTTP/1.1 %d %s\r\n", $!status.code, $!status);
        $out ~= sprintf("Content-Length: %d\r\n", $.body.chars);
        $out ~= "X-Server: Humming-Bird v$VERSION\r\n";
        for $.headers.pairs -> $pair { # TODO: There must be a nice way to destructure a pair.
            $out ~= sprintf("%s: %s\r\n", $pair.key, $pair.value);
        }
        $out ~= sprintf("\r\n%s", $.body);
    }
}

### ROUTING SECTION
class Route is Callable {
    has Str $.path;
    has &.callback;
    has @.middlewares is Array; # List of functions that type Request --> Request

    method CALL-ME(Request $req) {
        my $res = Response.new(status => HTTP::Status(200));
        if @!middlewares.elems {
            # Compose the middleware together using partial application
            # Finally, the main callback is added to the end of the chain
            @!middlewares.map({ .assuming($req, $res) }).reduce(-> &a, &b { &a(-> { &b }) })(&!callback.assuming($req, $res));
        } else {
            # If there is are no middlewares, just process the callback
            &!callback($req, $res);
        }
    }
}

# TODO: Globals kind of suck, but they work here. Maybe we can improve this.
our %ROUTES; # TODO: Should be un-modifiable after listen is called.
our $PARAM_IDX = ':';

sub split_uri(Str $uri --> List) {
    my @uri_parts = $uri.split('/', :skip-empty);

    if $uri eq '/' {
        @uri_parts[0] = '/';
    } else {
        @uri_parts.prepend('/');
    }

    @uri_parts.list;
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

    %loc{$meth} = $route;
}

sub dispatch_request(Request $request --> Response) {
    my @uri_parts = split_uri($request.path);
    if (@uri_parts.elems < 1) || (@uri_parts.elems == 1 && @uri_parts[0] ne '/') {
        return Response.new(status => HTTP::Status(400));
    }

    my %loc := %ROUTES;
    for @uri_parts -> $uri {
        my $possible_param = %loc.keys.first: *.starts-with($PARAM_IDX);

        if (not %loc{$uri}:exists) && (not $possible_param) {
            # TODO: Implement a way for the consumer to declare their own catch-all/404 handler (Maybe middleware?)
            return Response.new(status => HTTP::Status(404)).html('404 Not Found');
        } elsif $possible_param && (not %loc{$uri}:exists) {
            $request.params{$possible_param.match(/<[A..Z a..z 0..9 \- \_]>+/).Str} = $uri;
            %loc := %loc{$possible_param};
        } else {
            %loc := %loc{$uri};
        }
    }

    # If we don't support the request method on this route.
    if not %loc{$request.method}:exists {
        return Response.new(status => HTTP::Status(405)).html('405 Method Not Allowed');
    }

    %loc{$request.method}($request);
}

sub get(Str $path, &callback, @middlewares = []) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), GET);
}

sub put(Str $path, &callback, @middlewares = []) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), PUT);
}

sub post(Str $path, &callback, @middlewares = []) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), POST);
}

sub patch(Str $path, &callback, @middlewares = []) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), PATCH);
}

sub delete(Str $path, &callback, @middlewares = []) is export {
    delegate_route(Route.new(:$path, :&callback, :@middlewares), DELETE);
}

sub routes(--> Hash) is export {
    %ROUTES.clone;
}

sub listen(Int $port) is export {
    my HTTPServer $server = HTTPServer.new(port => $port);
    $server.listen(-> $raw_request {
        my Request $request = Request.encode($raw_request);
        start {
            my Bool $keep_alive = ($request.headers{'Connection'}:exists) && $request.headers{'Connection'} eq 'keep-alive';
            List.new(dispatch_request($request).decode, $keep_alive);
        }
    });
}

# vim: expandtab shiftwidth=4
