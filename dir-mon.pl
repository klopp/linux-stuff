#!/usr/bin/perl

# ------------------------------------------------------------------------------
use 5.014_000;
use utf8::all;
use open qw/:std :utf8/;
use strict;
use warnings;

# ------------------------------------------------------------------------------
use Const::Fast;
use English qw/-no_match_vars/;
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
const my $INOTYFY => 'inotifywait';
const my $RX_DATE => '(\d{4})[-](\d\d)[-](\d\d)';
const my $RX_TIME => '(\d\d):(\d\d):(\d\d)';
our $VERSION = 'v1.02';

# ------------------------------------------------------------------------------
my ( $cpid, $last_access, $ipid );
my ( $TIMEOUT, $INTERVAL, $PATH, $EXEC, $FORK, $QUIET, $DEBUG, $EXIT, $DRY ) = ( 60 * 10, 30 );

my $inotifywait = which $INOTYFY;
if ( !$inotifywait ) {
    print "No required '$INOTYFY' executable found!\n";
    exit 1;
}

# ------------------------------------------------------------------------------
GetOptions(
    'p|path=s'     => \$PATH,
    't|timeout=i'  => \$TIMEOUT,
    'i|interval=i' => \$INTERVAL,
    'e|exec=s'     => \$EXEC,
    'f|fork'       => \$FORK,
    'dry-run'      => \$DRY,
    'q|quiet'      => \$QUIET,
    'd|debug'      => \$DEBUG,
    'h|?|help'     => \&_usage,
    'x|exit'       => sub { $EXIT = 1 },
    'xx'           => sub { $EXIT = 2 },
);
( $EXEC && $PATH && -d $PATH && $TIMEOUT && $TIMEOUT =~ /^\d+$/sm && $INTERVAL && $INTERVAL =~ /^\d+$/sm )
    or _usage();

my @EXECUTABLE = quotewords( '\s+', 1, $EXEC );
for (@EXECUTABLE) {
    s/__PATH__/"$PATH"/gsm;
    s/__HOME__/$ENV{HOME}/gsm;
}

if ($FORK) {
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
local $OUTPUT_AUTOFLUSH = 1;
local $SIG{ALRM}        = \&_check_access_time;
local $SIG{TERM}        = \&_sig_x;
local $SIG{QUIT}        = \&_sig_x;
local $SIG{USR1}        = \&_sig_x;
local $SIG{USR1}        = \&_sig_x;
local $SIG{HUP}         = \&_sig_x;
local $SIG{INT}         = \&_sig_x;
$last_access = time;
alarm $INTERVAL;

my $icmd = sprintf '%s -q -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"', $inotifywait, $PATH;
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
        if ( $tdiff >= $TIMEOUT ) {
            _i( 'Timeout :: %u seconds!', $tdiff );
            if ( $DEBUG or $DRY ) {
                _log( q{!}, 'Run %s...', join q{ }, @EXECUTABLE );
            }
            else {
                _i( 'Run %s...', join q{ }, @EXECUTABLE );
            }
            my ( $rc, $out, $err ) = (-1);
            if ( !$DRY ) {
                my $h = start \@EXECUTABLE, sub { }, \$out, \$err;
                $h->finish;
                $rc = $h->full_result;
            }
            $out and _i( '%s', _trim($out) );
            $err and _i( '%s', _trim($err) );
            if ($EXIT) {
                if ( $EXIT == 1 ) {
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
    return alarm $INTERVAL;
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
    -f, -fork           fork and daemonize, STDOUT (not STDERR) must be redirected
    -q, -quiet          be quiet
    -d, -debug          print debug info
    -dry-run            do not run executable, print command line only
    -x, -exit           exit after SUCCESS external process (-e) result (**)
    -xx                 exit after ANY external process result (**)

*   __PATH__ and __HOME__ substrings will be rplaced by "-p" and $HOME values.
**  Always use -x or -xx if the directory will be unmounted by executable call.

Example:

    %s -x -q -dry-run -t 300 -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__"

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
    printf $USAGE, basename($PROGRAM_NAME), $TIMEOUT, $INTERVAL, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
sub _sig_x
{
    _i( 'Got signal "%s".', shift );
    exit;
}

# ------------------------------------------------------------------------------
END {
    $cpid or _log( q{!}, 'Stop all jobs and exit...' );
    if ($ipid) {
        killfam 'TERM', ($ipid);
        while ( ( my $kidpid = waitpid -1, WNOHANG ) > 0 ) {
            sleep 1;
        }
    }
}

# ------------------------------------------------------------------------------
sub _trim
{
    return $_[0] =~ s/^\s+|\s+$//gsmr;
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
    return printf "%s [%s] %s\n", _t(), $pfx, sprintf $fmt, @arg;
}

# ------------------------------------------------------------------------------
sub _i
{
    $QUIET or _log( q{-}, @_ );
}

# ------------------------------------------------------------------------------
sub _d
{
    $DEBUG and _log( q{*}, @_ );
}

# ------------------------------------------------------------------------------
