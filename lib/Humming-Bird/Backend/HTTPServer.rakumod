use v6;

# This code is based on the excellent code by the Raku community, adapted to work with Humming-Bird.
# https://github.com/raku-community-modules/HTTP-Server-Async

# A simple, single-threaded asynchronous HTTP Server.

use Humming-Bird::Backend;
use Humming-Bird::Glue;

unit class Humming-Bird::Backend::HTTPServer does Humming-Bird::Backend;

my constant $DEFAULT-RN = "\r\n\r\n".encode.Buf;
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

method !handle-request($data is rw, $index is rw, $connection) {
    my $request = {
        :$connection,
        data => Buf.new
    };

    my @header-lines = Buf.new($data[0..$index]).decode.lines.tail(*-1).grep({ .chars });
    return unless @header-lines.elems;

    $request<data> ~= $data.subbuf(0, $index);

    my $content-length = $data.elems - $index;
    for @header-lines -> $header {
        my ($key, $value) = $header.split(': ', 2, :skip-empty);
        given $key.lc {
            when 'content-length' {
                $content-length = +$value // ($data.elems - $index);
            }
            when 'transfer-encoding' {
                if $value.chomp.lc.index('chunked') !~~ Nil {
                    my Int $i;
                    my Int $b;
                    while $i < $data.elems {
                        $i++ while $data[$i] != $RN[0]
                                   && $data[$i+1] != $RN[1]
                                   && $i + 1 < $data.elems;

                        last if $i + 1 >= $data.elems;

                        $b = :16($data[0..$i].decode);
                        last if $data.elems < $i + $b;
                        if $b == 0 {
                            try $data .= subbuf(3);
                            last;
                        }

                        $i += 2;
                        $request<data> ~= $data.subbuf($i, $i+$b-3);
                        try $data .= subbuf($i+$b+2);
                        $i = 0;
                    }
                }
            }
        }
    }

    $request<data> ~= $data.subbuf($index, $content-length + 4);
    $.requests.send: $request;
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
                my Buf   $data .= new;
                my Int:D $idx   = 0;
                my $req;

                CATCH { default { .say } }
                $data ~= $bytes;
                %connection-map<last-active> = now;
                while $idx++ < $data.elems - 4 {
                    # Read up to headers
                    $idx--, last if $data[$idx] == $DEFAULT-RN[0]
                                    && $data[$idx+1] == $DEFAULT-RN[1]
                                    && $data[$idx+2] == $DEFAULT-RN[2]
                                    && $data[$idx+3] == $DEFAULT-RN[3];
                }

                $idx += 4;

                self!handle-request($data, $idx, %connection-map);
            }

            CATCH { default { .say; $connection.close; %connection-map<closed> = True } }
        }
    }
}

# vim: expandtab shiftwidth=4
