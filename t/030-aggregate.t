#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 1;
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
            Proto       => 'tcp',
        );
diag $! unless
    ok $us, 'connected';

my $ts = IO::Socket::INET->new(
            PeerAddr    => '127.0.0.1',
            PeerPort    => $port,
            Proto       => 'udp',
        );
diag $! unless
    ok $ts, 'connected';

no warnings 'redefine';

my @metrics;
sub DR::Statsd::Proxy::_aggregate {
    shift;
    push @metrics => \@_;
}



my $now = time;

ok $us->send("test.a.b.c 123 $now\n"), 'send udp 1';
ok $us->send("test.a.b.c 124 $now"), 'send udp 2';
ok $ts->print("test.c.d.e 123 $now\n"), 'send tcp 1';
ok $ts->print("test.c.d.e 124 $now\n"), 'send tcp 2';
close $ts;

Coro::AnyEvent::sleep 1.5;

note explain \@metrics;

ok $s->stop, 'stopped';
