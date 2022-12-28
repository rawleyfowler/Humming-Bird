=begin pod
=end pod

use v6;

unit module Humming-Bird::HTTPServer;

class HTTPServer is export {
    my Int $.port = 8080;

    method listen(&handler) {
        react {
            whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
                whenever $connection.Supply -> $request {
                    whenever &handler($request) -> $response {
                        $connection.print: $response;
                        $connection.close;
                    }
                }
            }
        }
    }
}

# vim: expandtab shiftwidth=4
