use v6;

unit module Humming-Bird::Test;

use Humming-Bird::Glue;
use HTTP::Status;

sub get-context(*%args) is export {
    my $req = Request.new(|%args);
    return [$req, Response.new(initiator => $req, status => HTTP::Status(200))];
}
