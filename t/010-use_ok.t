#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 1;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Statsd::Proxy';
}


