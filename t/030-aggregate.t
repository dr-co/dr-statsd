#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 19;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Statsd::Test';
    use_ok 'DR::Statsd::Proxy';

    use_ok 'Coro';
    use_ok 'Coro::AnyEvent';
}



my $port = free_port;
like $port => qr{^\d+$}, 'free port found';

my $rport = free_port;
like $rport => qr{^\d+$}, 'free port for remote found';

isnt $rport, $port, 'Ports are not the same';

my $s = new DR::Statsd::Proxy
                bind_port       => $port,
                parent          => "udp://127.0.0.1:$rport"
;

isa_ok $s => DR::Statsd::Proxy::, 'instance created';

ok $s->start, 'started';
        

my $us = IO::Socket::INET->new(
            PeerAddr    => '127.0.0.1',
            PeerPort    => $port,
            Proto       => 'udp',
        );
diag $! unless
    ok $us, 'UDP connected';

my $ts = IO::Socket::INET->new(
            PeerAddr    => '127.0.0.1',
            PeerPort    => $port,
            Proto       => 'tcp',
        );
diag $! unless
    ok $ts, 'TCP connected';

no warnings 'redefine';

my @metrics;
sub DR::Statsd::Proxy::_aggregate {
    shift;
    push @metrics => \@_;
}



my $now = time;

ok $us->send("udp.a.b.c 123 $now"), 'send udp 1';
ok $us->send("udp.a.b.c 124 $now"), 'send udp 2';
ok $ts->print("tcp.c.d.e 123 $now\n"), 'send tcp 1';
ok $ts->print("tcp.c.d.e 124 $now\n"), 'send tcp 2';
$ts->close;

Coro::AnyEvent::sleep .2;

is @metrics, 4, 'aggregate size';
my @tcp = grep { $_->[-1] eq 'tcp'  } @metrics;
my @udp = grep { $_->[-1] eq 'udp'  } @metrics;

is_deeply \@tcp,
    [
        [ 'tcp.c.d.e', 123, $now, 'tcp' ],
        [ 'tcp.c.d.e', 124, $now, 'tcp' ],
    ], 'tcp';

is_deeply \@udp,
    [
        [ 'udp.a.b.c', 123, $now, 'udp' ],
        [ 'udp.a.b.c', 124, $now, 'udp' ],
    ], 'udp';


ok $s->stop, 'stopped';
