use utf8;
use strict;
use warnings;

package DR::Statsd::Test;
use base qw(Exporter);
use IO::Socket::INET;
use feature 'state';

our @EXPORT = qw(
    free_port
    UTF
);

sub free_port() {
    state $busy_ports = {};
    while( 1 ) {
        my $port = 10000 + int rand 30000;
        next if exists $busy_ports->{ $port };
        next unless IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp',
            (($^O eq 'MSWin32') ? () : (ReuseAddr => 1)),
        );
        return $busy_ports->{ $port } = $port;
    }
}


sub UTF($) {
    my ($str) = @_;
    return $str unless defined $str;
    utf8::decode($str) unless utf8::is_utf8 $str;
    $str;
}

1;
