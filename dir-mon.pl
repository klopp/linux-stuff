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
use File::Basename qw/basename/;
use Getopt::Long qw/GetOptions/;
use IPC::Run qw/start/;
use POSIX qw/:sys_wait_h strftime setsid/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;

use Things::I2S;
use Things::Inotify;
use Things::Instance::LockSock;
use Things::Trim;

# ------------------------------------------------------------------------------
our $VERSION = 'v2.00';
const my $DEF_TIMEOUT  => ( 60 * 10 );
const my $DEF_INTERVAL => 10;
const my $DEF_LOCKDIR  => '/var/lock';
const my $EXE_NAME     => basename($PROGRAM_NAME);

# ------------------------------------------------------------------------------
my ( $cpid, $last_access );
my %opt = (
    timeout  => $DEF_TIMEOUT,
    interval => $DEF_INTERVAL,
    lockdir  => $DEF_LOCKDIR,
);

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

my $watcher = Things::Inotify->new(
    recurse => 1,
    path    => $opt{path},
    mode    => 'f',
);
if ( $watcher->error ) {
    _log( q{!}, '%s', $watcher->error );
    $cpid = $PID;
    exit 1;
}

my $lock = Things::Instance::LockSock->new->lock( file => $LOCKFILE );

if ( $lock->{errno} ) {
    _log( q{!}, '%s', $lock->{msg} );
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

$last_access = time;
alarm $opt{interval};
$watcher->run();
while ( my @events = $watcher->wait_for_events() ) {
    for (@events) {
        _d( '{%s} {%s} [%s]', _t( $_->{tstamp} ), $_->{path}, join( q{,}, @{ $_->{events} } ) );
        _check_access_time( undef, $_->{tstamp} );
    }
}

# ------------------------------------------------------------------------------
## no critic (RequireArgUnpacking)
sub _check_access_time
{
    CORE::state $guard = 0;
    return if ++$guard > 1;

    my ( $signal, $taccess ) = @_;

    $signal and _d( 'call %s() from ALRM', ( caller 0 )[3] );
    $signal or _d( 'call %s(%s) from inotify', ( caller 0 )[3], $taccess || q{?} );

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
            $out and _i( '%s', trim($out) );
            $err and _i( '%s', trim($err) );
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
    $opt{interval} = interval_to_seconds( $opt{interval} );
    $opt{timeout}  = interval_to_seconds( $opt{timeout} );
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
END {
    $cpid or _log( q{!}, 'Stop all jobs and exit...' );
    $LOCKFILE and unlink $LOCKFILE;
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
## no critic (RequireArgUnpacking)
sub _i
{
    return ( $opt{quiet} or _log( q{-}, @_ ) );
}

# ------------------------------------------------------------------------------
## no critic (RequireArgUnpacking)
sub _d
{
    return ( $opt{verbose} and _log( q{*}, @_ ) );
}

# ------------------------------------------------------------------------------
