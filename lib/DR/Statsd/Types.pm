use utf8;
use strict;
use warnings;

package DR::Statsd::Types;
use Mouse::Util::TypeConstraints;

enum AclType => [ 'suffix', 'default' ];


enum AggType    => [
    'min',
    'max',
    'avg',
    'sum',
    'latest'
];
1;
