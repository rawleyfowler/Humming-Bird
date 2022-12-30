=pod begin

=pod end

use v6;

unit module Humming-Bird::Middleware;

sub m_logger($request, $response, &next) is export {
    say sprintf("%s %s | %s %s", $request.method.raku, $request.path, $request.version, $request.header('User-Agent') || 'Unknown Agent');
    &next();
}

# vim: expandtab shiftwidth=4
