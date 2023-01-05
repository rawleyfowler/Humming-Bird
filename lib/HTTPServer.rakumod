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
                my $headers = "";
                my $content-length = -1;
                my $body = "";
                my $in-body = False;
                whenever $connection.Supply.lines -> $request {
                    say $request;
                    # If we're in the body
                    if $request.chars == 0 {
                        $in-body = True;
                        $headers ~= "\r\n";
                    }

                    # Get the content length
                    if $request.starts-with('Content-Length: ') {
                        $content-length = $request.split(': ')[1].Int || -1;
                    }

                    # If we know the request has a body
                    if ($content-length != -1) || $in-body {
                        $body ~= "$request";
                    } else {
                        $headers ~= "$request\r\n";
                    }

                    # If we've read all of the body of the request
                    # Or, if the request has no body
                    if ($body.chars eq $content-length) || ($in-body && ($content-length == -1)) {
                        whenever &handler($headers ~ $body) -> ($response, $keep-alive) {
                            $connection.print: $response;
                            unless $keep-alive {
                                $connection.close;
                            }
                        }

                        # Clean up
                        $headers = "";
                        $content-length = -1;
                        $body = "";
                        $in-body = False;
                    }
                }
            }
        }
    }
}

# vim: expandtab shiftwidth=4
