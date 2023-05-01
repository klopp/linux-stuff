#!/usr/bin/perl

# ------------------------------------------------------------------------------
use 5.014_000;
use utf8::all;
use open qw/:std :utf8/;
use strict;
use warnings;

# ------------------------------------------------------------------------------
use Const::Fast;
use Digest::MD5 qw/md5_hex/;
use English qw/-no_match_vars/;
use Fcntl qw/:DEFAULT :flock/;
use File::Basename qw/basename/;
use File::Which;
use Getopt::Long qw/GetOptions/;
use IPC::Open2;
use IPC::Run qw/start/;
use Lock::Socket qw/try_lock_socket/;
use Net::EmptyPort qw/empty_port/;
use POSIX qw/:sys_wait_h strftime setsid/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;
use Time::Local qw/timelocal_posix/;
use Time::Out qw/timeout/;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.05';
const my $DEF_TIMEOUT  => ( 60 * 10 );
const my $DEF_INTERVAL => 10;
const my $DEF_LOCKDIR  => '/var/lock';
const my $EXE_NAME     => basename($PROGRAM_NAME);
const my $INOTYFY      => 'inotifywait';
const my $RX_DATE      => '(\d{4})[-](\d\d)[-](\d\d)';
const my $RX_TIME      => '(\d\d):(\d\d):(\d\d)';

# ------------------------------------------------------------------------------
my ( $cpid, $last_access, $ipid );
my %opt = (
    timeout  => $DEF_TIMEOUT,
    interval => $DEF_INTERVAL,
    lockdir  => $DEF_LOCKDIR,
);

my $inotifywait = which $INOTYFY;
if ( !$inotifywait ) {
    print "No required '$INOTYFY' executable found!\n";
    exit 1;
}

# ------------------------------------------------------------------------------
GetOptions(
    \%opt,         'path|p=s',  'timeout|t=s', 'interval|i=s', 'exec|e=s', 'fork|f',
    'lockdir|l=s', 'd|dry-run', 'quiet|q',     'verbose|v',    'help|h|?', 'x|exit',
    'xx',
);
_check_opt() or _usage();

my @EXECUTABLE = quotewords( '\s+', 1, $opt{exec} );
for (@EXECUTABLE) {
    s/__PATH__/"$opt{path}"/gsm;
    s/__HOME__/$ENV{HOME}/gsm;
}

my $LOCKFILE = sprintf '%s/%s.%s', $opt{lockdir}, $EXE_NAME, md5_hex( $opt{path}, $opt{exec} );
local $OUTPUT_AUTOFLUSH = 1;

my $lock = _lock_instance($LOCKFILE);
if ( $lock->{errno} ) {
    if ( $lock->{reason} eq 'open' ) {
        _log( q{!}, 'Can not open file "%s" (%s)!', $LOCKFILE, $lock->{errno} );
    }
    elsif ( $lock->{reason} eq 'lock' ) {
        _log( q{!}, 'Can not lock process on port %u (%s)!', $lock->{port}, $lock->{errno} );
    }
    elsif ( $lock->{reason} eq 'write' ) {
        _log( q{!}, 'Can not write file "%s" (%s)!', $LOCKFILE, $lock->{errno} );
    }
    else {
        _log( q{!}, 'Unknown error reason (%s)!', $lock->{errno} );
    }
    $cpid = $PID;
    exit 1;
}

if ( $opt{fork} ) {
    _log( q{!}, 'Start deamonized...' );
    $cpid = fork;
    exit if $cpid;
    setsid;
    $cpid = fork;
    exit if $cpid;
    umask 0;
    chdir q{/};
    close *{STDIN};
}
else {
    _log( q{!}, 'Start...' );
}

# ------------------------------------------------------------------------------
use sigtrap qw/handler _signal_x normal-signals error-signals USR1 USR2/;
use sigtrap qw/handler _check_access_time ALRM/;

my $icmd = sprintf '%s -q -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"', $inotifywait, $opt{path};
_i( 'Run %s...', $icmd );
$ipid        = open2( my $stdout, undef, $icmd );
$last_access = time;
alarm $opt{interval};
while (1) {

    $_ = timeout $opt{interval} => sub { $stdout->getline };
    while ($_) {
        my $taccess;
        if (m{^
            $RX_DATE
            \s+
            $RX_TIME
            \s+
            (.*)
            \s+
            \[(.+)\]
        }xsm
            )
        {
            $taccess = timelocal_posix( $6, $5, $4, $3, $2 - 1, $1 - 1900 );
            _d( '{%s} {%s} {%s}', _t($taccess), $7, $8 );
        }
        _check_access_time( undef, $taccess );
        $_ = timeout $opt{interval} => sub { $stdout->getline };
    }
}

# ------------------------------------------------------------------------------
sub _check_access_time
{
    CORE::state $guard = 0;
    return if ++$guard > 1;

    my ( $signal, $taccess ) = @_;

    $signal and _d( 'call %s() from ALRM', ( caller(0) )[3] );
    $signal or _d( 'call %s(%s) from inotify', ( caller(0) )[3], $taccess || q{?} );

    my $tdiff = $taccess ? $taccess - $last_access : time - $last_access;
    if ( $tdiff > 0 ) {
        _d( 'No activity for %u sec.', $tdiff );
        if ( $tdiff >= $opt{timeout} ) {
            _i( 'Timeout :: %u seconds!', $tdiff );
            if ( $opt{verbose} or $opt{d} ) {
                _log( q{!}, 'Run %s...', join q{ }, @EXECUTABLE );
            }
            else {
                _i( 'Run %s...', join q{ }, @EXECUTABLE );
            }
            my ( $rc, $out, $err ) = (-1);
            if ( !$opt{d} ) {
                my $h = start \@EXECUTABLE, sub { }, \$out, \$err;
                $h->finish;
                $rc = $h->full_result;
            }
            $out and _i( '%s', _trim($out) );
            $err and _i( '%s', _trim($err) );
            if ( $opt{x} || $opt{xx} ) {
                if ( !$opt{xx} ) {
                    if ($rc) {
                        _i('External process return FAIL, reset timeout...');
                    }
                    else {
                        _i('External process return OK.');
                        exit;
                    }
                }
                else {
                    _i('External process finished.');
                    exit;
                }
            }
            $last_access = time;
        }
        else {
            $taccess and $last_access = $taccess;
        }
    }
    alarm $opt{interval};
    return $guard = 0;
}

# ------------------------------------------------------------------------------
sub _opt_error
{
    my ($opt) = @_;
    _log( q{!}, 'Invalid "-%s" option!', $opt );
    return;
}

# ------------------------------------------------------------------------------
# TODO :: move this function to private PERL5LIB
#
# PART:
#   \d+[s] - seconds, \d+[m] - minutes, \d+[h] - hours, \d+[d] - days
# IN string:
#   PART[{, }PART...]
# Example:
#   "1d, 24m, 3h, 30s"
#
# OR
#   "23:3:6:15" => 23 days, 3 hours, 6 minutes, 15 seconds
#   "3:6:15"    => 3 hours, 6 minutes, 15 seconds
#   etc
# ------------------------------------------------------------------------------
sub _interval_to_seconds
{
    my ($interval) = @_;
    my $seconds = 0;
    my @parts;

    if ( $interval =~ /^(\d+[:]?)+$/gsm ) {
        @parts = split /[:]/, $interval;
        $seconds += pop @parts;
        $seconds += pop(@parts) * 60           if @parts;
        $seconds += pop(@parts) * 60 * 60      if @parts;
        $seconds += pop(@parts) * 60 * 60 * 24 if @parts;
        return $seconds;
    }

    @parts = split /[,\s]+/sm, lc $interval;
    for (@parts) {
        return unless /^(\d+)([smhd]?)$/sm;
        if ( $2 eq 'm' ) {
            $seconds += $1 * 60;
        }
        elsif ( $2 eq 'h' ) {
            $seconds += $1 * 60 * 60;
        }
        elsif ( $2 eq 'd' ) {
            $seconds += $1 * 60 * 60 * 24;
        }
        else {
            $seconds += $1;
        }
    }
    return $seconds;
}

# ------------------------------------------------------------------------------
sub _check_opt
{
    if ( !$opt{path} || !-d $opt{path} ) {
        return _opt_error('path');
    }
    if ( !$opt{exec} ) {
        return _opt_error('exec');
    }
    if ( $opt{lockdir} && !-d $opt{lockdir} ) {
        return _opt_error('lock');
    }
    $opt{interval} = _interval_to_seconds( $opt{interval} );
    $opt{timeout}  = _interval_to_seconds( $opt{timeout} );
    $opt{interval} or return _opt_error('interval');
    $opt{timeout}  or return _opt_error('timeout');
    ( $opt{interval} < 10 || $opt{interval} > 60 ) and return _opt_error('interval');
    $opt{timeout} > 10 or return _opt_error('timeout');
    return 1;
}

# ------------------------------------------------------------------------------
sub _usage
{
    CORE::state $USAGE = <<'USAGE';

Usage: %s [options], where options are:

    -p, --path=PATH    directory to watch (required, see *)
    -t, --timeout=SEC  activity timeout (seconds, >= 10, default: %u)
    -i, --interval=SEC poll interval (seconds, >10 and <= 60, default: %u)
    -e, --exec=PATH    execute on activity timeout (required, see *)
    -l, --lockdir=PATH lock file directory, default: %s
    -f, --fork         fork and daemonize, STDOUT and STDERR must be redirected
    -q, --quiet        be quiet
    -v, --verbose      print debug info
    -d, --dry-run      do not run executable, print command line only
    -x, --exit         exit after SUCCESS external process (-e) result (**)
    -xx                exit after ANY external process result (**)

*   __PATH__ and __HOME__ substrings will be rplaced by "-p" and $HOME values.
**  Always use -x or -xx if the directory will be unmounted by executable call.

Example:

    %s -x -f -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__" >> /tmp/d.log 2>&1

umount.sh example:

    #!/bin/bash
    LSOF=$(lsof "$1" | awk 'NR>1 {print $2}' | sort -n | uniq)
    if [[ -z "$LSOF" ]]; then
        sudo umount -l "$1"
        exit 0
    else
        echo -e "Directory "$1" used by:\n$(ps --no-headers -o command -p ${LSOF})"
        exit 1
    fi

USAGE
    printf $USAGE, $EXE_NAME, $DEF_TIMEOUT, $DEF_INTERVAL, $DEF_LOCKDIR, $EXE_NAME;

    # supress exit message:
    $cpid = $PID;
    exit 1;
}

# ------------------------------------------------------------------------------
sub _signal_x
{
    _i( 'Got signal "%s".', shift );
    exit;
}

# ------------------------------------------------------------------------------
sub _lock_instance
{
    my ($lockfile) = @_;

    my ( $lock, $port, $fh );
    if ( !sysopen $fh, $lockfile, O_RDWR | O_CREAT ) {
        return { reason => 'open', errno => $ERRNO, };
    }
    binmode $fh;
    sysread $fh, $port, 64;
    $port and $port =~ s/^\s+|\s+$//gsm;
    if ( !$port || $port !~ /^\d+$/sm ) {
        $port = empty_port();
    }
    if ( !( $lock = try_lock_socket($port) ) ) {
        close $fh;
        return { port => $port, reason => 'lock', errno => $ERRNO, };
    }
    if ( !flock( $fh, LOCK_EX ) || !truncate( $fh, 0 ) || !syswrite( $fh, $port, length $port ) ) {
        close $fh;
        return { reason => 'write', errno => $ERRNO, };
    }
    close $fh;
    return $lock;
}

# ------------------------------------------------------------------------------
END {
    $cpid or _log( q{!}, 'Stop all jobs and exit...' );
    if ($ipid) {
        _d( 'Send TERM to [%u] pid tree...', $ipid );
        killfam 'TERM', ($ipid);
        while ( ( my $kidpid = waitpid -1, WNOHANG ) > 0 ) {
            sleep 1;
        }
        unlink $LOCKFILE;
    }
}

# ------------------------------------------------------------------------------
sub _trim
{
    my ($s) = @_;
    $s and $s =~ s/^\s+|\s+$//gsm;
    return $s;
}

# ------------------------------------------------------------------------------
sub _t
{
    my ($t) = @_;
    $t //= time;
    return strftime '%F %X', localtime $t;
}

# ------------------------------------------------------------------------------
sub _log
{
    my ( $pfx, $fmt, @arg ) = @_;
    return printf "%s [%s] [%u] %s\n", _t(), $pfx, $PID, sprintf $fmt, @arg;
}

# ------------------------------------------------------------------------------
sub _i
{
    return ( $opt{quiet} or _log( q{-}, @_ ) );
}

# ------------------------------------------------------------------------------
sub _d
{
    return ( $opt{verbose} and _log( q{*}, @_ ) );
}

# ------------------------------------------------------------------------------
