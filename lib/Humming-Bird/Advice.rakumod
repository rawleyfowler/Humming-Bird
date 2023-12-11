use Humming-Bird::Core;
use Humming-Bird::Glue;

unit module Humming-Bird::Advice;

sub advice-logger(Humming-Bird::Glue::Response:D $response --> Humming-Bird::Glue::Response:D) is export {
    my $log = "{ $response.status.Int } { $response.status } | { $response.initiator.path } | ";
	$log ~= $response.header('Content-Type') ?? $response.header('Content-Type') !! "no-content";
	$response.log: $log;
}
