=begin pod
=end pod

use v6;

unit module Humming-Bird::HTTPServer;

class HTTPServer is export {
    my Int $.port = 8080;

    method listen(&handler) {
        react {
            say "Humming-Bird listening on port http://localhost:$.port";
            whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
                # TODO: Figure out how to handle this https://docs.raku.org/type/IO::Socket::Async#method_Supply
                # Specifically: the fact that post request bodies will ALWAYS not have the last byte included unless there is a work around.
                whenever $connection.Supply.Channel -> $request {
                    say $request;
                    whenever &handler($request) -> ($response, $keep_alive) {
                        $connection.print: $response;
                        $connection.close unless $keep_alive;
                    }
                }
            }
        }
    }
}

# vim: expandtab shiftwidth=4
