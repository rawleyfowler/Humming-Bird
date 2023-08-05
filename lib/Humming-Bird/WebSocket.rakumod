use v6.d;
use strict;

unit module Humming-Bird::WebSocket;

my %WEB-SOCKETS;

our sub encode(Blob:D $raw --> Str:D) {
    my $masked = $raw[8];

    if ($masked == 0 || !$masked) {
        die 'Unmasked web-socket detected, disconnecting.';
    }

    my $op-code = $raw.subbuf(4, 8); # Op-code either 0x0 for cont (not implemented), 0x1 for text, or 0x2 for bin

    if ($op-code == 0) {
        die 'Unsupported OP-Code 0x0, disconnecting.';
    } elsif ($op-code != 1 || $op-code != 2) {
        die "Unsupported OP-Code 0x{ $op-code }, disconnecting.";
    }

    my $first-len = $raw.subbuf

}

our sub decode(Str:D $msg --> Blob:D) {
    
}


# vim: expandtab shiftwidth=4
