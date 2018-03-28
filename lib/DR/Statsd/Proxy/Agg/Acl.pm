use utf8;
use strict;
use warnings;

package DR::Statsd::Proxy::Agg::Acl;
use Mouse;
use Mouse::Util::TypeConstraints;

use DR::Statsd::Types;


has type    => is => 'ro', isa => 'AclType', required => 1;
has method  => is => 'ro', isa => 'AggType', required => 1;

has value   => is => 'ro', isa => 'Maybe[Str]';


# разделитель для suffix
has _div => is => 'rw', isa => 'Maybe[Str]';


sub BUILD {
    my ($self, $args) = @_;

    if ($self->type eq 'suffix') {
        die "value required for acl.type == suffix\n"
            unless defined $self->value;

        my $d = quotemeta($args->{divider} // '.');
        $d = quotemeta('.') unless length $d;
        $self->_div($d);
    }
}


sub pass {
    my ($self, $name) = @_;


    goto $self->type;


    suffix: {
        return undef unless $name;
        my @sp = split($self->_div, $name);
        return undef unless @sp;
        return undef unless $sp[-1] eq $self->value;
        return $self->method;
    }

    default:
        return $self->method;

}

__PACKAGE__->meta->make_immutable;
