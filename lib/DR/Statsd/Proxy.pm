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
use Scalar::Util 'looks_like_number';
use Errno qw(EINTR EAGAIN);
use DR::Statsd::Proxy::Agg::Acl;
use DR::Statsd::Proxy::Agg;
use IO::Socket;
use IO::Socket::INET;
use Socket;

has parent_host     => is => 'ro', isa => 'Str', default => '127.0.0.1';
has parent_port     => is => 'ro', isa => 'Str', default => 2003;
has parent_lag      => is => 'ro', isa => 'Int', default => 5;
has truncate_timestamp  =>
    is      => 'ro',
    isa     => 'Int',
    default => 1;



has bind_host       => is => 'ro', isa => 'Maybe[Str]', default => '127.0.0.1';
has bind_port       => is => 'ro', isa => 'Str', default => '2004';
has tcp_timeout     => is => 'ro', isa => 'Num', default => 1;

has acls            =>
    is      => 'ro',
    isa     => 'ArrayRef[DR::Statsd::Proxy::Agg::Acl]',
    default => sub {[]};

has agg             =>
    is      => 'ro',
    isa     => 'HashRef[DR::Statsd::Proxy::Agg]',
    default => sub {{}};



has _started        => is => 'rw', isa => 'Bool', default => 0;
has _tcp            => is => 'rw', isa => 'Maybe[Object]';
has _udp            => is => 'rw', isa => 'Maybe[Object]';
has _workers        => is => 'ro', isa => 'HashRef', default => sub {{}};
has _list           => is => 'ro', isa => 'ArrayRef', default => sub {[]};
has _fh             => is => 'rw', isa => 'Maybe[Object]';

sub start {
    my ($self) = @_;
    croak 'Server is already _started' if $self->_started;


    $self->_started(1);


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

    $self->_pusher;

    $self;
}


sub _aggregate {
    my ($self, $name, $value, $time, $proto) = @_;
    #my $now = AnyEvent::now();
    my $now = $time;
    if ($self->truncate_timestamp) {
        $time = int $time;
        $time -= $time % $self->truncate_timestamp;
    }
    push @{ $self->_list } => [ $now, [ $name, $value, $time ] ];
}

sub _line_received {
    my ($self, $line, $proto) = @_;
    my $now = int AnyEvent::now();
    my ($name, $value, $stamp) = split /\s+/, $line, 4;

    return unless looks_like_number $stamp;
    return unless looks_like_number $value;
    return unless length $name;
    $self->_aggregate($name, $value, $stamp, $proto);
}


sub _udp_datagram {
    my ($self) = @_;
    sub {
        return unless $self->_started;
        my ($data, $fh, $client_addr) = @_;
        if (defined $data and length $data) {
            my @lines = split /\n/, $data;
            for (@lines) {
                s/\s+$//s;
                $self->_line_received($_, 'udp');
            }
        }
    }
}

sub _tcp_client {
    my ($self) = @_;
    sub {
        my ($fh, $host, $port) = @_;
        unless ($self->_started) {
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

    $fh->timeout($self->tcp_timeout);;

    while ($self->_started) {
        my $line = $fh->readline("\n");
        unless (defined $line) {
            next if $! == EAGAIN;
            last;
        }
        unless (length $line) {
            next;
        }

        $line =~ s/\s+$//s;
        $self->_line_received($line, 'tcp');
    }

    $fh->close;

    delete $self->_workers->{$no};
}

sub _pusher {
    my ($self) = @_;
    $self->_workers->{0} = async {
        DEBUGF 'Pusher started';
        my $started = AnyEvent::now();
        while ($self->_started) {
            Coro::AnyEvent::sleep 0.1;
            my $now = AnyEvent::now();
            next if $now - $started < 1;
            $started = $now;
            $self->_flush(0);
        }
        $self->_flush(1);
        DEBUGF 'Pusher was done';
    };
}

sub _flush {
    my ($self, $force) = @_;

    return unless @{ $self->_list };
    my $to = AnyEvent::now();
    if ($force) {
        $to += 1_000_000;
    } else {
        $to -= $self->parent_lag;
        $to -= $self->truncate_timestamp;
    }

    while (@{ $self->_list }) {
        my $f = $self->_list->[0];
        last unless $to >= $f->[0];

        $f = shift(@{ $self->_list })->[1];


        my $method;
        for my $acl (@{ $self->acls }) {
            $method = $acl->pass($f->[0]);
            last if $method;
        }
        next unless $method;

        my $agg = $self->agg->{$method};

        unless ($agg) {
            $agg = $self->agg->{$method} =
                new DR::Statsd::Proxy::Agg type => $method;
        }

        $agg->put(@$f);
    }

    for my $agg (values %{ $self->agg }) {
        my $list = $agg->flush;
        $self->_send_parent($list);
    }
    
}

sub stop {
    my ($self) = @_;
    $self->_started(0);

    while (%{ $self->_workers }) {
        my ($fno) = keys %{ $self->_workers };
        my $coro = delete $self->_workers->{$fno};
        $coro->join;
    }
    $self;
}

sub _send_parent {
    my ($self, $list) = @_;
    return unless @$list;
    unless ($self->_fh) {
        my $fh = new IO::Socket::INET
                        PeerPort        => $self->parent_port,
                        PeerHost        => $self->parent_host,
                        Proto           => 'udp';
        unless ($fh) {
            my $e = $!;
            utf8::decode $e unless utf8::is_utf8 $e;
            die "Can not connect to parent: $e";
        }
        $self->_fh($fh);
    }
    SEND: while (@$list) {
        my $pkt = '';
        while (length($pkt) < 3800) {

            my $m = shift @$list;
            last unless defined $m;
            $pkt .= sprintf "%s %s %s\n", @$m;
        }

        last unless length $pkt;
        $self->_fh->send($pkt);
    }
}

sub wait_signal {
    my ($self) = @_;
    my $coro;
    local $SIG{INT} = sub {
        DEBUGF 'INT signal';
        $coro->ready if $coro;
    };
    local $SIG{TERM} = sub {
        DEBUGF 'TERM signal';
        $coro->ready if $coro;
    };
    $coro = $Coro::current;
    Coro::schedule;
    undef $coro;
}
__PACKAGE__->meta->make_immutable;
