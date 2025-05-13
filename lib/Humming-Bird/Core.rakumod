use v6.d;
use strict;

use HTTP::Status;
use Humming-Bird::Backend::HTTPServer;
use Humming-Bird::Glue;

unit module Humming-Bird::Core;

our constant $VERSION = '4.0.0';

### ROUTING SECTION
my constant $PARAM_IDX     = ':';
my constant $CATCH_ALL_IDX = '**';

our %ROUTES;
our @MIDDLEWARE;
our @ADVICE = [{ $^a }];
our %ERROR;
our @PLUGINS;

class Route {
    has Str:D $.path is required where { ($^a eq '') or $^a.starts-with('/') };
    has Bool:D $.static = False;
    has &.callback is required;
    has @.middlewares; # List of functions that type Request --> Request

    method CALL-ME(Request:D $req, $tmp?) {
        my Response:D $res = $tmp ?? $tmp !! Response.new(initiator => $req, status => HTTP::Status(200));

        my @middlewares = [|@!middlewares, |@MIDDLEWARE, -> $a, $b, &c { &!callback($a, $b) }];

        # The current route is converted to a middleware.
        if @middlewares.elems > 1 {
            # For historical purposes this code will stay here, unfortunately, it was not performant enough.
            # This code was written on the first day I started working on Humming-Bird. - RF
            # state &comp = @middlewares.prepend(-> $re, $rp, &n { &!callback.assuming($req, $res) }).map({ $^a.raku.say; $^a.assuming($req, $res) }).reverse.reduce(-> &a, &b { &b.assuming(&a) } );

            for @middlewares -> &middleware {
                my Bool:D $next = False;
                &middleware($req, $res, sub { $next = True } );
                last unless $next;
            }
        }
        else {
            # If there is are no middlewares, just process the callback
            &!callback($req, $res);
        }

        return $res;
    }
}

sub split_uri(Str:D $uri --> List:D) {
    my @uri_parts = $uri.split('/', :skip-empty);
    @uri_parts.prepend('/').List;
}

sub delegate-route(Route:D $route, HTTPMethod:D $meth --> Route:D) {
    die 'Route cannot be empty' unless $route.path;
    die "Invalid route: { $route.path }, routes must start with a '/'" unless $route.path.contains('/');

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
    has @!advice = ( { $^a } ); # List of functions that type Response --> Response

    method !add-route(Route:D $route, HTTPMethod:D $method --> Route:D) {
        my &advice = [o] @!advice;
        my &cb = $route.callback;
        my $r = $route.clone(path => $!root ~ $route.path,
                             middlewares => [|$route.middlewares, |@!middlewares],
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

    method plugin($plugin) {
        @PLUGINS.push: $plugin;
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

sub dispatch-request(Request:D $request, Response:D $response) {
    my @uri_parts = split_uri($request.path);
    if (@uri_parts.elems < 1) || (@uri_parts.elems == 1 && @uri_parts[0] ne '/') {
        return $response.status(404);
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

            return $response.status(404);
        } elsif $possible-param && !%loc{$uri} {
            $request.params{~$possible-param.match(/<[A..Z a..z 0..9 \- \_]>+/)} = $uri;
            %loc := %loc{$possible-param};
        } else {
            %loc := %loc{$uri};
        }

		# If the route could possibly be static
        with %loc{$request.method} {
            if %loc{$request.method}.static {
	            return %loc{$request.method}($request, $response);
            }
        }
    }

    # For HEAD requests we should return a GET request. The decoder will delete the body
    if $request.method === HEAD {
        if %loc{GET}:exists {
            return %loc{GET}($request, $response);
        } else {
            return $response.status(405).html('<h1>405 Method Not Allowed</h1>');
        }
    }

    # If we don't support the request method on this route.
    without %loc{$request.method} {
        return $response.status(405).html('<h1>405 Method Not Allowed</h1>');
    }

    return %loc{$request.method}($request, $response);

    # This is how we pass to error advice.
    CATCH {
        when %ERROR{.^name}:exists { return %ERROR{.^name}($_, $response.status(500)) }
        default {
            my $err = $_;
            with %*ENV<HUMMING_BIRD_ENV> {
                if .lc ~~ 'prod' | 'production' {
                    return $response.status(500).html('<h1>500 Internal Server Error</h1>, Something went very wrong on our end!!');
                }
            }
            return $response.status(500).html("<h1>500 Internal Server Error</h1><br><i> $err <br> { $err.backtrace.nice } </i>");
        }
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

	my sub callback(Humming-Bird::Glue::Request:D $request, Humming-Bird::Glue::Response:D $response) {
		return $response.status(400) if $request.path.contains: '..';
		my $cut-size = $path.ends-with('/') ?? $path.chars !! $path.chars + 1;
        my $file = $static-path.add($request.path.substr: $cut-size, $request.path.chars);

        return $response.status(404) unless $file.e;

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

sub plugin(Str:D $plugin, **@args --> Array:D) is export {
   @PLUGINS.push: [$plugin, @args];
}

sub handle(Humming-Bird::Glue::Request:D $request) {
    my $response = Response.new(initiator => $request, status => HTTP::Status(200));
    dispatch-request($request, $response);

    for @ADVICE -> &advice {
        &advice($response);
    }

    return $response;
}

sub listen(Int:D $port, Str:D $addr = '0.0.0.0', :$no-block, :$timeout = 3, :$backend = Humming-Bird::Backend::HTTPServer) is export {
    use Terminal::ANSIColor;
    my $server = $backend.new(:$port, :$addr, :$timeout);

    for @PLUGINS -> [$plugin, @args] {
        my $fq = 'Humming-Bird::Plugin::' ~ $plugin;
        {
            {
                require ::($fq);
                CATCH {
                    default {
                        die "It doesn't look like $fq is a valid plugin? Are you sure it's installed?\n\n$_";
                    }
                }
            }

            use MONKEY;
            my $instance;
            EVAL "use $fq; \$instance = $fq.new;";
            my Any $mutations = $instance.register($server, %ROUTES, @MIDDLEWARE, @ADVICE, |@args);

            if $mutations ~~ Hash {
                for $mutations.keys -> $mutation {
                    my &method = $mutations{$mutation};
                    Humming-Bird::Glue::HTTPAction.^add_method($mutation, &method);
                }
            }

            say "Plugin: $fq ", colored('✓', 'green');

            CATCH {
                default {
                    die "Something went wrong registering plugin: $fq\n\n$_";
                }
            }
        }
    }

    say(
        colored('Humming-Bird', 'green'),
        " listening on port http://$addr:$port",
        "\n"
    );

    say(
        colored('Warning', 'yellow'),
        ': Humming-Bird is currently running in DEV mode, please set HUMMING_BIRD_ENV to PROD or PRODUCTION to enable PRODUCTION mode.',
        "\n"
    ) if (%*ENV<HUMMING_BIRD_ENV>:exists && %*ENV<HUMMING_BIRD_ENV>.Str.lc ~~ 'prod' | 'production');

    if $no-block {
        start {
            $server.listen(&handle);
        }
    } else {
        $server.listen(&handle);
    }
}
