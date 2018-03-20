use utf8;
use warnings;
use strict;
use feature 'state';

package DR::Statsd::Proxy::Debug;
use base qw(Exporter);
our @EXPORT = qw(
    EMERG  ALERT  FATAL  CRIT  ERROR  WARN  NOTICE  INFO  DEBUG
    EMERGF ALERTF FATALF CRITF ERRORF WARNF NOTICEF INFOF DEBUGF
);
our @EXPORT_OK = @EXPORT;

use Encode                  qw(decode_utf8 encode_utf8);
use JSON::XS                qw(encode_json);
use Sys::Syslog             qw();
use File::Basename          qw(basename);
use Data::Dumper;
use POSIX                   qw(strftime);

our $VERSION = '0.31';
# Отключить лог
our $DISABLE = 0;
# Выводить отладку в STDOUT
our $VERBOSE = $ENV{DEBUG} ?1 :0;

# Программа по умолчанию
our $PROGRAM = 'statsd-perl';
# Идентификатор
our $FACILITY = 'local7';
# Опции
our $LOGOPT = 'ndelay,pid';

# Открытие лога
sub openlog{
    unless( state $opened ) {
        Sys::Syslog::openlog($PROGRAM, $LOGOPT, $FACILITY);
        $opened = 1;
    }
    return 1;
}

# Закрытие лога
sub closelog {
    Sys::Syslog::closelog();
}

# Разбор параметров и запись в лог
sub _write_log {

    # Пропустим если выключены все варианты вывода
    return if $DISABLE and !$VERBOSE;

    openlog;

    my (@bodies, @tags, $module, $file, $line);

    my $level = shift;
    my $title = shift;
    push @bodies => shift if @_ % 2;

    my $next_title;
    # идем по именам ключей
    for (my $i = 0; $i < @_; $i += 2) {
        if ($_[ $i ] eq '-t') {
            next unless defined $_[ $i + 1 ];
            push @tags => $_[ $i + 1 ];
            next;
        }

        if ($_[ $i ] eq '-file') {
            $file = $_[ $i + 1 ];
            next;
        }

        if ($_[ $i ] eq '-line') {
            $line = $_[ $i + 1 ];
            next;
        }

        if ($_[ $i ] eq '-module') {
            $line = $_[ $i + 1 ];
            next;
        }

        if ($_[ $i ] eq '-b') {
            my $b = $_[ $i + 1 ];

            my ($msg_title, $msg_body) = (undef, $b);
            $msg_title = $next_title if $next_title;
            if ('HASH' eq ref $b) {
                $msg_title = $b->{title};
                $msg_body  = $b->{body};
            }
            push @bodies => [ $msg_title, $msg_body ];
            $next_title = undef;
            next;
        }

        if ($_[ $i ] eq '-d') {
            local $Data::Dumper::Indent = 0;
            local $Data::Dumper::Terse = 1;
            local $Data::Dumper::Useqq = 1;
            local $Data::Dumper::Deepcopy = 1;
            local $Data::Dumper::Maxdepth = 0;
            local $Data::Dumper::Sortkeys = 1;
            my $dump = Data::Dumper->Dump([ $_[ $i + 1] ]);
            $dump =~ s/(\\x\{[\da-fA-F]+\})/eval "qq{$1}"/eg;

            push @bodies => [ $next_title || 'Dumper', $dump ];
            $next_title = undef;
            next;
        }

        if ($_[ $i ] eq '-s') {
            $next_title = $_[ $i + 1 ];
            next;
        }
    }

    # Определим откуда вызывали, если не передавали параметрами
    ($module, $file, $line) = caller
        unless defined $module and defined $file and defined $line;

    # Если включен вывод в терминал то выведим сообщения
    if($VERBOSE) {
        my ($message, @opts) = @_;

        $| = 1 unless $|;

        my $time = strftime("%Y-%m-%dT%H:%M:%S", localtime);

        my $verb  = sprintf "%s [%s in %s on %s line %s]\n",
            $title, uc($level), $time, $module => $line;

        # Для тестов выведем отладку в специальном формате
        if($0 =~ m{\.t$}) {
            require Test::More;
            Test::More::note $verb;
        } else {
            print STDOUT $verb;
        }
    }

    # Если выключено то не выводим с syslog
    return if $DISABLE;

    my @opts = (
        \@tags,
        $title,
        \@bodies,
        [
            $file => $line,
            $ENV{TAXI_LOG_URL},
            $ENV{TAXI_LOG_USER},
            $ENV{TAXI_LOG_IP},
        ],
    );

    # TODO: закоментировать если че не так, пойдет опять в JSON
    {
        my $lout;
        if (@tags) {
            $lout = sprintf '[%s] ', join ',' => @tags;
        } else {
            $lout = '';
        }

        $title =~ s/\s*$//s;
        $lout .= $title . " ";
        for my $body (@bodies) {
            next unless $body;
            $body = [ $body ] unless ref $body;
            next unless @$body;

            $lout .= ' < ';
            for (@$body) {
                next unless defined $_;
                s/\s+$//s;
                s/^/  /gsm;
                $lout .= "$_ ";
            }
            $lout .= '>';
        }

        $lout .= " at $file line $line";
        $lout .= ", $ENV{TAXI_LOG_URL}" if $ENV{TAXI_LOG_URL};
        $lout .= ", $ENV{TAXI_LOG_USER}" if $ENV{TAXI_LOG_USER};
        $lout .= ", $ENV{TAXI_LOG_IP}" if $ENV{TAXI_LOG_IP};
        return Sys::Syslog::syslog($level, encode_utf8 $lout);
    }

    return Sys::Syslog::syslog($level, encode_json \@opts);
}

=head1 FUNCTIONS

Основные функции для уровней syslog.

=head2 EMERG $header, $message, @opts

Cообщения с уровнем 'emerg'. Система неработоспособна. Необходимо немедленное
уведомление персонала о случившимся через СМС или дургие быстрые и доступные
средства.

=cut

sub EMERG {
    unshift @_ => 'emerg';
    goto \&_write_log;
}

=head2 ALERT $header, $message, @opts

Cообщения с уровнем 'alert'. Ошибки с данным уровнем должны быть исправлены
немедленно. Об ошибках с данным уровнем должены быть уведомлены люди
поддерживающие данный проект.

=cut

sub ALERT {
    unshift @_ => 'alert';
    goto \&_write_log;
}

=head2 FATAL $header, $message, @opts или CRIT $header, $message, @opts

Cообщения с уровнем 'crit'. Ошибки с данным уровнем должны быть исправлены
немедленно, хоть и означают неисправности во второстепенных системах.

=cut

sub FATAL {
    unshift @_ => 'crit';
    goto \&_write_log;
}

sub CRIT {
    unshift @_ => 'crit';
    goto \&_write_log;
}

=head2 ERROR $header, $message, @opts

Cообщения с уровнем 'error'. Не критичные ошибки. Сообщения данного уровня
должны быть переданы разработчикам и исправлены в ближайшее время.

=cut

sub ERROR {
    unshift @_ => 'err';
    goto \&_write_log;
}

=head2 WARN $header, $message, @opts

Cообщения с уровнем 'warn'. Предупреждения (но не ошибки). Говорит о скором
возникновении ошибки. Должны быть рассмотрены в ближайшее время чтоб не
допустить возникновения самой ошибки.

=cut

sub WARN {
    unshift @_ => 'warning';
    goto \&_write_log;
}

=head2 NOTICE $header, $message, @opts

Cообщения с уровнем 'notice'. Сигнализирует о потенциальных проблемах. Такие
сообщения собираются логом и отправляются разработчикам на доработки.

=cut

sub NOTICE {
    unshift @_ => 'notice';
    goto \&_write_log;
}

=head2 INFO $header, $message, @opts

Cообщения с уровнем 'info'. Обычные уведомляющие сообщения. Не требуют действий.

=cut

sub INFO {
    unshift @_ => 'info';
    goto \&_write_log;
}

=head2 DEBUG $header, $message, @opts

Cообщения с уровнем 'debug'. Используются разработчиками для отладки.
Выключены в рабочем режиме программы.

=cut

sub DEBUG {
    unshift @_ => 'debug';
    goto \&_write_log;
}


=head1 FUNCTIONS LIKE SPRINTF

Дополнительные функции, ведущие себя как sprintf.

=cut

# Выкорчевывает параметры для sprintf, собирает сообщение и передает переданной
# стандартной функции.
sub _write_log_f {
    my $sub     = shift;
#    my $header  = shift;
    my $message = shift;
    my @opts;

    # Опции бререм как все значения до порвого тега
    for my $i ( 0 .. @_-1 ) {
        last if not @_;
        last if $_[$i] && $_[$i] =~  m{^-[a-z]};

        push @opts, splice @_, $i, 1;
#        print Dumper [\@opts, \@_];
        redo;
    }

    if( @opts ) {
        @opts = map { defined $_ ? $_ : 'undef' } @opts;
        $message = sprintf $message, @opts;
    }

    unshift @_, '';
    unshift @_, $message;

    goto $sub;
}

=head2 EMERGF $header, $message, @args, @opts

=cut

sub EMERGF {
    unshift @_ => \&EMERG;
    goto \&_write_log_f;
}

=head2 ALERTF $header, $message, @args, @opts

=cut

sub ALERTF {
    unshift @_ => \&ALERT;
    goto \&_write_log_f;
}

=head2 FATALF $header, $message, @args, @opts

=cut

sub FATALF {
    unshift @_ => \&FATAL;
    goto \&_write_log_f;
}

=head2 CRITF $header, $message, @args, @opts

=cut

sub CRITF {
    unshift @_ => \&CRIT;
    goto \&_write_log_f;
}

=head2 ERRORF $header, $message, @args, @opts

=cut

sub ERRORF {
    unshift @_ => \&ERROR;
    goto \&_write_log_f;
}

=head2 WARNF $header, $message, @args, @opts

=cut

sub WARNF {
    unshift @_ => \&WARN;
    goto \&_write_log_f;
}

=head2 NOTICEF $header, $message, @args, @opts

=cut

sub NOTICEF {
    unshift @_ => \&NOTICE;
    goto \&_write_log_f;
}

=head2 INFOF $header, $message, @args, @opts

=cut

sub INFOF {
    unshift @_ => \&INFO;
    goto \&_write_log_f;
}

=head2 DEBUGF $header, $message, @args, @opts

=cut

sub DEBUGF {
    unshift @_ => \&DEBUG;
    goto \&_write_log_f;
}

1;

=head1 COPYRIGHT

Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>

Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

All rights reserved. If You want to use the code You
MUST have permissions from Dmitry E. Oboukhov AND
Roman V Nikolaev.

=cut

