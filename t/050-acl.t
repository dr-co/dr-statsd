#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 9;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Statsd::Proxy::Agg::Acl';
}


for my $acl (new DR::Statsd::Proxy::Agg::Acl
        type    => 'suffix',
        method  => 'sum',
        value   => 'count'
        
    ) {

    is $acl->pass('a.b.c'),     undef, 'broken suffix';
    is $acl->pass('a.b.count'), 'sum', 'detected suffix';
    is $acl->pass('count'), 'sum', 'detected suffix';
    is $acl->pass(), undef, 'no suffix';
}

for my $acl (new DR::Statsd::Proxy::Agg::Acl
        type    => 'default',
        method  => 'max',
        value   => 'count'
        
    ) {

    is $acl->pass('a.b.c'),     'max', 'broken suffix';
    is $acl->pass('a.b.count'), 'max', 'detected suffix';
    is $acl->pass('count'),     'max', 'detected suffix';
    is $acl->pass(),            'max', 'no suffix';
}
