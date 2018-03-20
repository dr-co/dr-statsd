use utf8;
use strict;
use warnings;

package DR::Statsd::Proxy;
use DR::Statsd::Proxy::Debug;
use Mouse;
use URI;
use Coro;
use Carp;
use AnyEvent::Socket;
use Coro::AnyEvent;
use Coro::Handle;
use AnyEvent::Handle::UDP;
use Mouse::Util::TypeConstraints;

subtype PUrl => as 'URI';

coerce PUrl =>
    from    'Str',
    via     { URI->new($_) };


has parent      => is => 'ro', isa => 'PUrl', required => 1, coerce => 1;
has bind_host   => is => 'ro', isa => 'Maybe[Str]', default => '127.0.0.1';
has bind_port   => is => 'ro', isa => 'Str', default => '2004';
has lag         => is => 'ro', isa => 'Int', default => 5;


has started     => is => 'rw', isa => 'Bool', default => 0;

has _tcp        => is => 'rw', isa => 'Maybe[Object]';
has _udp        => is => 'rw', isa => 'Maybe[Object]';

has _workers    => is => 'ro', isa => 'HashRef', default => sub {{}};

sub start {
    my ($self) = @_;
    croak 'Server is already started' if $self->started;


    $self->started(1);


    DEBUGF 'Creating TCP-server: %s:%s', $self->bind_host, $self->bind_port;
    my $tcp = tcp_server
                    $self->bind_host,
                    $self->bind_port,
                    $self->_tcp_client;

    $self->_tcp($tcp);


    my $udp = new AnyEvent::Handle::UDP
        bind        => [ $self->bind_host, $self->bind_port ],
        on_recv     => $self->_udp_datagram
    ;

    $self->_udp($udp);

    $self;
}

sub _line_received {
    my ($self, $line, $proto) = @_;
    DEBUGF '%s %s', $proto, $line;
}


sub _udp_datagram {
    my ($self) = @_;
    sub {
        return unless $self->started;
        my ($data, $fh, $client_addr) = @_;
        if (defined $data and length $data) {
            my @lines = split /\n/, $data;
            for (@lines) {
                s/\s+$//s;
                $self->_line_received($_, "udp://$client_addr");
            }
        }
    }
}


sub _tcp_client {
    my ($self) = @_;
    sub {
        my ($fh, $host, $port) = @_;
        unless ($self->started) {
            DEBUGF 'Client %s:%s connected while server is stopping',
                $host,
                $port;
            close $fh;
            return;
        }

        my $no = fileno $fh;
        my $cfh = new_from_fh Coro::Handle $fh;

        $self->_workers->{$no} =
        async {
            $self->_tcp_client_chat(@_);
        } $cfh, $host, $port, $no;
    }
}

sub _tcp_client_chat {
    my ($self, $fh, $host, $port, $no) = @_;


    DEBUGF 'TCP client %s:%s connected', $host, $port;
    $fh->timeout(.5);

    while ($self->started) {
        my $line = $fh->readline("\n");
        last unless defined $line;
        next unless length $line;

        $line =~ s/\s+$//s;
        $self->_line_received($line, "tcp://$host:$port");
    }

    delete $self->_workers->{$no};
}


sub stop {
    my ($self) = @_;
    $self->started(0);

    while (%{ $self->_workers }) {
        my ($fno) = keys %{ $self->_workers };
        my $coro = delete $self->_workers->{$fno};
        $coro->join;
    }
    $self;
}
__PACKAGE__->meta->make_immutable;
