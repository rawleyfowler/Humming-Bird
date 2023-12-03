use v6.d;
use strict;

use HTTP::Status;
use Humming-Bird::Backend::HTTPServer;
use Humming-Bird::Glue;

unit module Humming-Bird::Core;

our constant $VERSION = '3.0.3';

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

	my sub callback(Humming-Bird::Glue::Request:D $request, Humming-Bird::Glue::Response:D $response) {
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

sub handle(Humming-Bird::Glue::Request:D $request) {
    return ([o] @ADVICE).(dispatch-request($request));
}

sub listen(Int:D $port, Str:D $addr = '0.0.0.0', :$no-block, :$timeout = 3, :$backend = Humming-Bird::Backend::HTTPServer) is export {
    my $server = $backend.new(:$port, :$addr, :$timeout);

    say "Humming-Bird listening on port http://localhost:$port";
    if $no-block {
        start {
            $server.listen(&handle);
        }
    } else {
        $server.listen(&handle);
    }
}
