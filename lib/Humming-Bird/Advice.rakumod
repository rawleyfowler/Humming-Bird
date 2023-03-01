=begin pod
=head1 Humming-Bird::Advice

Simple advice for the Humming-Bird web-framework. Advice are end-of-cycle
middlewares. They take a Response and return a Response.

=head2 Exported advice

=head3 advice-logger

=for code
    use Humming-Bird::Core;
    use Humming-Bird::Advice;
	advice(&advice-logger);

This advice will concisely log all traffic leaving the application.

=end pod

use v6;

use Humming-Bird::Core;

unit module Humming-Bird::Advice;

sub advice-logger(Response:D $response --> Response) is export {
	say "{ $response.status.Int } { $response.status } | { $response.initiator.path } | { $response.header('Content-Type') }";
	$response;
}
