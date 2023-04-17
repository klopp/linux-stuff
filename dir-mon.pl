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
use Fcntl qw/:DEFAULT :flock SEEK_SET/;
use File::Basename qw/basename/;
use File::Which;
use Getopt::Long qw/GetOptions/;
use IPC::Open2;
use IPC::Run qw/start/;
use POSIX qw/:sys_wait_h strftime setsid/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;
use Time::Local qw/timelocal_posix/;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.04';
const my $DEF_TIMEOUT  => ( 60 * 10 );
const my $DEF_INTERVAL => 30;
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
    \%opt,         'path|p=s',    'timeout|t=s', 'interval|i=s', 'exec|e=s', 'fork|f',
    'lockdir|l=s', 'dry|dry-run', 'quiet|q',     'debug|d',      'help|h|?', 'x|exit',
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
my $lock = _check_self_instance();

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
    print {$lock} "$PID\n";
    close $lock;
}
else {
    close $lock;
    _log( q{!}, 'Start...' );
}

# ------------------------------------------------------------------------------
local $SIG{ALRM} = \&_check_access_time;
local $SIG{TERM} = \&_sig_x;
local $SIG{QUIT} = \&_sig_x;
local $SIG{USR1} = \&_sig_x;
local $SIG{USR1} = \&_sig_x;
local $SIG{HUP}  = \&_sig_x;
local $SIG{INT}  = \&_sig_x;
$last_access = time;
alarm $opt{interval};

my $icmd = sprintf '%s -q -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"', $inotifywait, $opt{path};
_i( 'Run %s...', $icmd );
$ipid = open2( my $stdout, undef, $icmd );

while (<$stdout>) {

    next unless m{^
        $RX_DATE
        \s+
        $RX_TIME
        \s+
        (.*)
        \s+
        \[(.+)\]
    }xsm;

    my $taccess = timelocal_posix( $6, $5, $4, $3, $2 - 1, $1 - 1900 );
    _d( '[%04d-%02d-%02d %02d:%02d:%02d] %s {%s}', $1, $2, $3, $4, $5, $6, $7, $8 );
    _check_access_time( undef, $taccess );
}

# ------------------------------------------------------------------------------
sub _check_access_time
{
    my ( undef, $taccess ) = @_;

    my $tdiff = $taccess ? $taccess - $last_access : time - $last_access;
    if ( $tdiff > 0 ) {
        _d( 'No activity for %u sec.', $tdiff );
        if ( $tdiff >= $opt{timeout} ) {
            _i( 'Timeout :: %u seconds!', $tdiff );
            if ( $opt{debug} or $opt{dry} ) {
                _log( q{!}, 'Run %s...', join q{ }, @EXECUTABLE );
            }
            else {
                _i( 'Run %s...', join q{ }, @EXECUTABLE );
            }
            my ( $rc, $out, $err ) = (-1);
            if ( !$opt{dry} ) {
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
    return alarm $opt{interval};
}

# ------------------------------------------------------------------------------
sub _opt_error
{
    my ($opt) = @_;
    _log( q{!}, 'Invalid "-%s" option!', $opt );
    return;
}

# ------------------------------------------------------------------------------
# Part:
#   \d+[s] - seconds
#   \d+m   - minutes
#   \d+h   - hours
#   \d+d   - days
# IN string:
#   PART[{, }PART...]
# Example:
#   "1d, 3h, 24m, 30s"
# ------------------------------------------------------------------------------
sub _interval_to_seconds
{
    # TODO :: move to private PERL5LIB
    my ($interval) = @_;
    my @parts      = split /[,\s]+/sm, $interval;
    my $seconds    = 0;

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
    return 1;
}

# ------------------------------------------------------------------------------
sub _usage
{
    CORE::state $USAGE = <<'USAGE';

Usage: %s [options], where options are:

    -?, -h, -help       this message
    -p, -path     PATH  directory to watch (required, see *)
    -t, -timeout  SEC   activity timeout (seconds, default: %u)
    -i, -interval SEC   poll interval (seconds, default: %u)
    -e, -exec     PATH  execute on activity timeout (required, see *)
    -l, -lockdir  PATH  lock file directory, default: %s
    -f, -fork           fork and daemonize, STDOUT (not STDERR) must be redirected
    -q, -quiet          be quiet
    -d, -debug          print debug info
    -dry, dry-run       do not run executable, print command line only
    -x, -exit           exit after SUCCESS external process (-e) result (**)
    -xx                 exit after ANY external process result (**)

*   __PATH__ and __HOME__ substrings will be rplaced by "-p" and $HOME values.
**  Always use -x or -xx if the directory will be unmounted by executable call.

Example:

    %s -x -q -t 300 -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__"

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
sub _sig_x
{
    _i( 'Got signal "%s".', shift );
    exit;
}

# ------------------------------------------------------------------------------
sub _check_self_instance
{
    my ( $pid, $fh );
    if ( !sysopen( $fh, $LOCKFILE, O_RDWR | O_CREAT ) || !flock( $fh, LOCK_EX ) ) {
        _log( q{!}, 'Error writing lock file "%s" (%s)!', $LOCKFILE, _trim($ERRNO) );
        $fh and close $fh;

        # supress exit message:
        $cpid = $PID;
        exit 1;

    }
    $pid = _trim(<$fh>);
    if ( $pid and $pid =~ /^\d+$/sm and kill 0 => $pid ) {
        _log( q{!}, 'Active instance (PID: %s) found!', $pid );
        close $fh;

        # supress exit message:
        $cpid = $PID;
        exit 1;
    }
    $fh->autoflush(1);
    sysseek $fh, 0, SEEK_SET;
    print {$fh} "$PID\n";
    sysseek $fh, 0, SEEK_SET;
    return $fh;
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
    return strftime '%F %X', localtime;
}

# ------------------------------------------------------------------------------
sub _log
{
    my ( $pfx, $fmt, @arg ) = @_;
    return printf "[%u] %s [%s] %s\n", $PID, _t(), $pfx, sprintf $fmt, @arg;
}

# ------------------------------------------------------------------------------
sub _i
{
    return ( $opt{quiet} or _log( q{-}, @_ ) );
}

# ------------------------------------------------------------------------------
sub _d
{
    return ( $opt{debug} and _log( q{*}, @_ ) );
}

# ------------------------------------------------------------------------------
