=begin pod
=end pod

use v6;

class Humming-Bird::HTTPServer is export {
    has Int $.port = 8080;

    method listen(&handler) {
        react {
            say "Humming-Bird listening on port http://localhost:$.port";
            whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
                whenever $connection.Supply: :bin -> $bin-request { # Has to be bin because of: https://docs.raku.org/type/IO::Socket::Async#method_Supply
                    my $request = $bin-request.decode.Str;
                    whenever &handler($request) -> ($response, $keep-alive) {
                        $connection.print: $response;
                        $connection.close unless $keep-alive;
                    }
                }
            }
        }
    }
}

# vim: expandtab shiftwidth=4
