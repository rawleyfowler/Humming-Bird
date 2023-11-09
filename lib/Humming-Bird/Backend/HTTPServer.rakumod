use v6;

# This code is based on the excellent code by the Raku community, adapted to work with Humming-Bird.
# https://github.com/raku-community-modules/HTTP-Server-Async

# A simple, single-threaded asynchronous HTTP Server.

use Humming-Bird::Backend;
use Humming-Bird::Glue;

unit class Humming-Bird::Backend::HTTPServer does Humming-Bird::Backend;

my constant $RNRN = "\r\n\r\n".encode.Buf;
my constant $RN = "\r\n".encode.Buf;

has Channel:D $.requests .= new;
has Lock $!lock .= new;
has @!connections;

method !timeout {
    start {
        react {
            whenever Supply.interval(1) {
                CATCH { default { warn $_ } }
                $!lock.protect({
                    @!connections = @!connections.grep({ !$_<closed>.defined }); # Remove dead connections
                    for @!connections.grep({ now - $_<last-active> >= $!timeout }) {
                        {
                            $_<closed> = True;
                            $_<socket>.write(Blob.new);
                            $_<socket>.close;

                            CATCH { default { warn $_ } }
                        }
                    }
                });
            }
        }
    }
}

method !respond(&handler) {
    start {
        react {
            whenever $.requests -> $request {
                CATCH { default { .say } }
                my $hb-request = Humming-Bird::Glue::Request.decode($request<data>);
                my Humming-Bird::Glue::Response $response = &handler($hb-request);
                $request<connection><socket>.write: $response.encode;
                $request<connection><closed> = True with $hb-request.header('keep-alive');
            }
        }
    }
}

method listen(&handler) {
    react {
        self!timeout;
        self!respond(&handler);

        whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
            my %connection-map := {
                socket => $connection,
                last-active => now
            }

            $!lock.protect({ @!connections.push: %connection-map });

            whenever $connection.Supply: :bin -> $bytes {
                CATCH { default { .say } }
                %connection-map<last-active> = now;
                $.requests.send: {
                    connection => %connection-map,
                    data => $bytes;
                };
            }

            CATCH { default { .say; $connection.close; %connection-map<closed> = True } }
        }
    }
}

# vim: expandtab shiftwidth=4
