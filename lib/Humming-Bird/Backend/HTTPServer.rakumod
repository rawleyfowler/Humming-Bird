use v6;

# This code is based on the excellent code by the Raku community, adapted to work with Humming-Bird.
# https://github.com/raku-community-modules/HTTP-Server-Async

# A simple, single-threaded asynchronous HTTP Server.

use Humming-Bird::Backend;
use Humming-Bird::Glue;
use HTTP::Status;

unit class Humming-Bird::Backend::HTTPServer does Humming-Bird::Backend;

my constant $RNRN = "\r\n\r\n".encode.Buf;
my constant $RN = "\r\n".encode.Buf;

has Channel:D $.requests .= new;
has Lock $!lock .= new;
has IO::Socket::Async::ListenSocket $!socket handles <close>;
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
    state $four-eleven = sub ($initiator) {
        Humming-Bird::Glue::Response.new(:$initiator, status => HTTP::Status(411)).encode;
    };

    start {
        react {
            whenever $.requests -> $request {
                CATCH {
                    when X::IO {
                        $request<socket>.write: $four-eleven($request<request>);
                        $request<closed> = True;
                    }
                    default { .say }
                }
                my $hb-request = $request<request>;
                my Humming-Bird::Glue::Response $hb-response = &handler($hb-request);
                $request<socket>.write: $hb-response.encode;
                $request<request>:delete; # Mark this request as handled.
                $request<closed> = False with $hb-request.header('keep-alive');
            }
        }
    }
}

method listen(&handler) {
    react whenever signal(SIGINT) { self.close; }
        
    react {
        self!timeout;
        self!respond(&handler);
        $!socket = IO::Socket::Async.listen($.addr // '0.0.0.0', $.port);
        whenever $!socket -> $connection {
            my %connection-map := {
                socket => $connection,
                last-active => now
            }

            whenever $connection.Supply: :bin -> $bytes {
                CATCH { default { .say } }
                %connection-map<last-active> = now;

                my $header-request = False;
                if %connection-map<request>:!exists {
                    %connection-map<request> = Humming-Bird::Glue::Request.decode($bytes);
                    $header-request = True;
                }

                my $hb-request = %connection-map<request>;
                if !$header-request {
                    $hb-request.body.append: $bytes;
                }

                my $content-length = $hb-request.header('Content-Length');
                if (!$content-length.defined || ($hb-request.body.bytes == $content-length)) {
                    $.requests.send: %connection-map;
                }
            }

            CATCH { default { .say; $connection.close; %connection-map<closed> = True } }
        }
    }
}

# vim: expandtab shiftwidth=4
