#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 6;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Statsd::Proxy::Agg';
}

subtest 'Agg latest' => sub {
    plan tests => 6;

    my $stamp1 = time;
    my $stamp2 = $stamp1 + 1;

    my $agg = new DR::Statsd::Proxy::Agg type => 'latest';
    ok $agg => 'Instance created';

    for (1 .. 10) {
        $agg->put('test', $_, $stamp1);
        $agg->put('tesa', $_ + 21, $stamp2);
    }
    is $agg->size, 2, 'size';
    is_deeply
        $agg->flush,
        [
            [ test => 10,       $stamp1 ],
            [ tesa => 10 + 21,  $stamp2 ]
        ],
        'flush';
    is $agg->size, 0, 'size after flush';
    is_deeply $agg->_list, {}, 'internal storage';
    is_deeply $agg->flush, [], 'empty flush';
};

subtest 'Agg min' => sub {
    plan tests => 5;

    my $stamp1 = time;
    my $stamp2 = $stamp1 + 1;

    my $agg = new DR::Statsd::Proxy::Agg type => 'min';
    ok $agg => 'Instance created';

    for (1 .. 10) {
        $agg->put('test', $_, $stamp1);
        $agg->put('tesa', $_ + 21, $stamp2);
    }
    is $agg->size, 2, 'size';
    is_deeply
        $agg->flush,
        [
            [ test => 1,        $stamp1 ],
            [ tesa => 1 + 21,   $stamp2 ]
        ],
        'flush';
    is $agg->size, 0, 'size after flush';
    is_deeply $agg->_list, {}, 'internal storage';
};

subtest 'Agg max' => sub {
    plan tests => 5;

    my $stamp1 = time;
    my $stamp2 = $stamp1 + 1;

    my $agg = new DR::Statsd::Proxy::Agg type => 'max';
    ok $agg => 'Instance created';

    for (1 .. 10) {
        $agg->put('test', 20 - $_, $stamp1);
        $agg->put('tesa', 22 - $_, $stamp2);
    }
    is $agg->size, 2, 'size';
    is_deeply
        $agg->flush,
        [
            [ test => 19,        $stamp1 ],
            [ tesa => 21,        $stamp2 ]
        ],
        'flush';
    is $agg->size, 0, 'size after flush';
    is_deeply $agg->_list, {}, 'internal storage';
};

subtest 'Agg avg' => sub {
    plan tests => 5;

    my $stamp1 = time;
    my $stamp2 = $stamp1 + 1;

    my $agg = new DR::Statsd::Proxy::Agg type => 'avg';
    ok $agg => 'Instance created';

    my ($sum1, $sum2) = (0, 0);

    for (1 .. 10) {
        $sum1 += 20 - $_;
        $sum2 += 22 - $_;
        $agg->put('test', 20 - $_, $stamp1);
        $agg->put('tesa', 22 - $_, $stamp2);
    }
    is $agg->size, 2, 'size';
    is_deeply
        $agg->flush,
        [
            [ test => $sum1 / 10,   $stamp1 ],
            [ tesa => $sum2 / 10,   $stamp2 ]
        ],
        'flush';
    is $agg->size, 0, 'size after flush';
    is_deeply $agg->_list, {}, 'internal storage';
};

subtest 'Agg sum' => sub {
    plan tests => 5;

    my $stamp1 = time;
    my $stamp2 = $stamp1 + 1;

    my $agg = new DR::Statsd::Proxy::Agg type => 'sum';
    ok $agg => 'Instance created';

    my ($sum1, $sum2) = (0, 0);

    for (1 .. 10) {
        $sum1 += 20 - $_;
        $sum2 += 22 - $_;
        $agg->put('test', 20 - $_, $stamp1);
        $agg->put('tesa', 22 - $_, $stamp2);
    }
    is $agg->size, 2, 'size';
    is_deeply
        $agg->flush,
        [
            [ test => $sum1,   $stamp1 ],
            [ tesa => $sum2,   $stamp2 ]
        ],
        'flush';
    is $agg->size, 0, 'size after flush';
    is_deeply $agg->_list, {}, 'internal storage';
};
