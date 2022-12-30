=begin pod
=head1 Humming-Bird::Middleware

Simple middleware for the Humming-Bird web-framework.

=head2 Exported middlewares

=head3 m_logger

=for code
    use Humming-Bird::Core;
    use Humming-Bird::Middleware;
    get('/', -> $request, $response {
        $response.html('<h1>Hello World!</h1>');
    }, [ &m_logger ]);

This middleware will concisely log all traffic traffic heading for this route.

=end pod

use v6;

unit module Humming-Bird::Middleware;

sub m_logger($request, $response, &next) is export {
    say sprintf("%s %s | %s %s", $request.method.Str, $request.path, $request.version, $request.header('User-Agent') || 'Unknown Agent');
    &next();
}

# vim: expandtab shiftwidth=4
