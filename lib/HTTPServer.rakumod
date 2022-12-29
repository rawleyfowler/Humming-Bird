=begin pod
=end pod

use v6;

unit module Humming-Bird::HTTPServer;

class HTTPServer is export {
    my Int $.port = 8080;

    method listen(&handler) {
        react {
            # TODO: Implement some real "logging", this can be added when Middleware is implemented
            say "Listening on port http://localhost:$.port";
            whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
                whenever $connection.Supply -> $request {
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
