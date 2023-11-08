use v6.d;

use Humming-Bird::Core;
use Humming-Bird::Glue;

use UUID::V4;

unit module Humming-Bird::Middleware;

my constant $SESSION-NAME = 'HB_SESSION';

sub middleware-logger(Request:D $request, Response:D $response, &next) is export {
    $request.log(sprintf("%s | %s | %s | %s", $request.method.Str, $request.path, $request.version, $request.header('User-Agent') || 'Unknown Agent'));
    &next();
}

class Session {
    has Str:D $.id = uuid-v4;
    has Instant:D $.expires is required;
    has %!stash handles <AT-KEY>;
}

# Defaults to 24 hour sessions
sub middleware-session(Int:D :$ttl = (3600 * 24), Bool:D :$secure = False) is export {
    state Lock $lock .= new;
    state %sessions;
    state $session-cleanup = False;

    sub aux(Request:D $request, Response:D $response, &next) is export {
        my $session-id = $request.cookie($SESSION-NAME).?value;
        if $session-id and %sessions{$session-id}:exists {
            $lock.protect({ $request.stash<session> := %sessions{$session-id} });
        } else {
            my $session = Session.new(expires => now + $ttl);
            $lock.protect({ %sessions{$session.id} = $session });
            $request.stash<session> := $session;
            $response.cookie($SESSION-NAME, $session.id, expires => DateTime.new($session.expires), :$secure);
        }

        &next();
    }

    start {
        $session-cleanup = True;
        react whenever Supply.interval(1) {
            $lock.protect({ %sessions = %sessions.grep({ ($_.value.expires - now) > 0 }) });
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
    }, [ middleware-logger(expiry => 4500, :secure) ]);

This middleware allows a route to access the users session

=end pod
