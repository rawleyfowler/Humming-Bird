=begin pod
=head1 Humming-Bird::Middleware

Simple middleware for the Humming-Bird web-framework.

=head2 Exported middlewares

=head3 middleware-logger

=for code
    use Humming-Bird::Core;
    use Humming-Bird::Advice;
	advice(&advice-logger);

This advice will concisely log all traffic leaving this route.

=end pod

use v6;

use Humming-Bird::Core;

unit module Humming-Bird::Advice;

sub advice-logger(Response $response --> Response) is export {
	say "{ $response.status.Int } { $response.status } | { $response.header('Content-Type') }";
	$response;
}
