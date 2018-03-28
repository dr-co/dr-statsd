use utf8;
use strict;
use warnings;

package DR::Statsd::Proxy::Agg;
use Mouse;
use DR::Statsd::Types;

has type        => is => 'ro', isa => 'AggType', required => 1;

has _list       => is => 'rw', isa => 'HashRef', default => sub {{}};

has size        =>
    is      => 'ro',
    isa     => 'Int',
    default => sub { 0 },
    writer  => '_set_size';

sub put {
    my ($self, $name, $value, $time) = @_;
    
    $time = int $time;

    $self->_list->{$time} //= {};

    my $chunk = $self->_list->{$time};

    goto $self->type;


    min:
        unless ($chunk->{$name}) {
            $chunk->{$name} = { v => $value };
            $self->_set_size($self->size + 1);
            return;
        }
        if ($value < $chunk->{$name}{v}) {
            $chunk->{$name}{v} = $value;
            return;
        }
        
        return;


    max:
        unless ($chunk->{$name}) {
            $chunk->{$name} = { v => $value };
            $self->_set_size($self->size + 1);
            return;
        }
        if ($value > $chunk->{$name}{v}) {
            $chunk->{$name}{v} = $value;
            return;
        }
        
        return;
    
    avg:
        unless ($chunk->{$name}) {
            $chunk->{$name} = { v => $value, s => $value, count => 1 };
            $self->_set_size($self->size + 1);
            return;
        }
        $chunk->{$name}{'s'} += $value;
        $chunk->{$name}{'count'}++;
        $chunk->{$name}{'v'} = $chunk->{$name}{'s'} / $chunk->{$name}{'count'};
        return;

    sum:
        unless ($chunk->{$name}) {
            $chunk->{$name} = { v => $value };
            $self->_set_size($self->size + 1);
            return;
        }
        $chunk->{$name}{'v'} += $value;
        return;

    latest:
        $self->_set_size($self->size + 1) unless $chunk->{$name};
        $chunk->{$name} = { v => $value };
        return;
}

sub flush {

    my ($self) = @_;
    my @res;
    for my $time (sort { $a <=> $b } keys %{ $self->_list }) {
        my $chunk = $self->_list->{$time};
        for (sort keys %$chunk) {
            push @res => [ $_, $chunk->{$_}{v}, $time ];
        }
    }

    $self->_list({});
    $self->_set_size(0);
    \@res;
}

__PACKAGE__->meta->make_immutable;
