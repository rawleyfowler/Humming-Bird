use v6;

# This code is based on the excellent code by the Raku community with a few adjustments and code style changes.
# https://github.com/raku-community-modules/HTTP-Server-Async

my constant $DEFAULT-RN = "\r\n\r\n".encode.Buf;
my constant $RN = "\r\n".encode.Buf;

class Humming-Bird::HTTPServer is export {
    has Int:D $.port = 8080;
    has Int:D $.timeout is required;
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
                        for @!connections.grep({ (now - $_<last-active> >= $!timeout) && (!$_<websocket>.defined && !$_<closed>.defined) }) {
                            $_<closed> = True;
                            $_<socket>.write(Blob.new);
                            $_<socket>.close;

                            CATCH { default { warn $_ } }
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
                    my ($response, $keep-alive) = &handler($request);
                    $request<connection><socket>.write: $response;
                    $request<connection><closed> = True unless ($keep-alive || $request<connection><websocket>.defined);
                }
            }
        }
    }

    method !handle-request($data is rw, $index is rw, $connection is rw) {
        my $request = {
            :$connection,
            data => Buf.new
        };

        my @header-lines = Buf.new($data[0..$index]).decode.lines.tail(*-1).grep({ .chars });
        return unless @header-lines.elems;

        $request<data> ~= $data.subbuf(0, $index);

        my $content-length = $data.elems - $index;
        my $upgrade = False;
        for @header-lines -> $header {
            my ($key, $value) = $header.split(': ', :skip-empty);
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
                when 'upgrade' {
                    if $value.chomp.lc.index('websocket') !~~ Nil {
                        $upgrade = True;
                    }
                }
            }
        }

        $request<data> ~= $data.subbuf($index, $content-length+4);
        $request<upgrade> = $upgrade;
        $.requests.send: $request;
    }

    method listen(&handler) {
        react {
            say "Humming-Bird listening on port http://localhost:$.port";

            self!timeout;
            self!respond(&handler);

            whenever IO::Socket::Async.listen('0.0.0.0', $.port) -> $connection {
                my %connection-map := {
                    socket => $connection,
                    last-active => now
                }

                $!lock.protect({ @!connections.push: %connection-map });

                whenever $connection.Supply: :bin -> $bytes {
                    %connection-map<last-active> = now;

                    my Buf   $data .= new;
                    $data ~= $bytes;

                    if !%connection-map<websocket>.defined {
                        my Int:D $idx   = 0;
                        CATCH { default { .say } }
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
                }

                CATCH { default { .say; $connection.close; %connection-map<closed> = True } }
            }
        }
    }
}

# vim: expandtab shiftwidth=4

=begin pod
A simple async HTTP server that does its best to follow HTTP/1.1
=end pod
