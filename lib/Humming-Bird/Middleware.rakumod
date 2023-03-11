use v6.d;

use Humming-Bird::Core;

use UUID::V4;

unit module Humming-Bird::Middleware;

my constant $SESSION-NAME = 'HB_SESSION';

sub middleware-logger(Request:D $request, Response:D $response, &next) is export {
    say sprintf("%s %s | %s %s", $request.method.Str, $request.path, $request.version, $request.header('User-Agent') || 'Unknown Agent');
    &next();
}

class Session {
    has Str:D $.id = uuid-v4;
    has Instant:D $.expiry is required;
    has %!stash handles <AT-KEY>;
}

sub middleware-session(:$expiry = 3600) is export {
    state Lock $lock .= new;
    state %sessions;
    state $session-cleanup = False;

    sub aux(Request:D $request, Response:D $response, &next) is export {
        if (my $session-id = $request.cookie($SESSION-NAME)) {
            $lock.protect({ $request.stash<session> = %sessions{$session-id} with %sessions{$session-id} });
        } else {
            my $session = Session.new(expiry => now + $expiry);
            $lock.protect({ %sessions{$session.id} = $session });
            $request.stash<session> = $session;
            $response.cookie($SESSION-NAME, $session.id, DateTime.new($session.expiry));
        }
    }

    start {
        $session-cleanup = True;
        react whenever Supply.interval(1) {
            $lock.protect({ %sessions = %sessions.grep({ ($_.value.expiry - now) gt 0 }) });
        }
    } unless $session-cleanup;
    
    &aux;
}

# vim: expandtab shiftwidth=4

=begin pod
=head1 Humming-Bird::Middleware

Simple middleware for the Humming-Bird web-framework.

=head2 Exported middlewares

=head3 middleware-logger

=for code
    use Humming-Bird::Core;
    use Humming-Bird::Middleware;
    get('/', -> $request, $response {
        $response.html('<h1>Hello World!</h1>');
    }, [ &middleware-logger ]);

This middleware will concisely log all traffic heading for this route.

=head3 middleware-session

= for code
    use Humming-Bird::Core;
    use Humming-Bird::Middleware;
    get('/', -> $request, $response {
        $response.html('<h1>Hello World!</h1>');
    }, [ &middleware-logger ]);

This middleware allows a route to access the users session.

=end pod
