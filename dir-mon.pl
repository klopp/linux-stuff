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
const my $EXE_NAME => basename($PROGRAM_NAME);
const my $INOTYFY  => 'inotifywait';
const my $RX_DATE  => '(\d{4})[-](\d\d)[-](\d\d)';
const my $RX_TIME  => '(\d\d):(\d\d):(\d\d)';

# ------------------------------------------------------------------------------
my ( $cpid, $last_access, $ipid );
my %opt = (
    timeout  => ( 60 * 10 ),
    interval => 30,
    lock     => '/var/lock',
);

my $inotifywait = which $INOTYFY;
if ( !$inotifywait ) {
    print "No required '$INOTYFY' executable found!\n";
    exit 1;
}

# ------------------------------------------------------------------------------
GetOptions(
    \%opt,      'path|p=s',    'timeout|t=i', 'interval|i=i', 'exec|e=s', 'fork|f',
    'lock|l=s', 'dry|dry-run', 'quiet|q',     'debug|d',      'help|h|?', 'x|exit',
    'xx',
);
_check_opt() or _usage();

my @EXECUTABLE = quotewords( '\s+', 1, $opt{exec} );
for (@EXECUTABLE) {
    s/__PATH__/"$opt{path}"/gsm;
    s/__HOME__/$ENV{HOME}/gsm;
}

my $LOCKFILE = sprintf '%s/%s.%s', $opt{lock}, $EXE_NAME, md5_hex( $opt{path}, $opt{exec} );
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
    printf "Invalid '-%s' option!\n", $opt;
    return;
}

# ------------------------------------------------------------------------------
sub _valid_number
{
    my ($key) = @_;
    if ( $opt{$key} && $opt{$key} =~ /^\d+$/sm ) {
        return 1;
    }
    return _opt_error($key);
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
    if ( $opt{lock} && !-d $opt{lock} ) {
        return _opt_error('lock');
    }
    return _valid_number('interval') && _valid_number('timeout');
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
    -l, -lock           lock file directory, default: %s
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
    printf $USAGE, $EXE_NAME, $opt{timeout}, $opt{interval}, $opt{lock}, $EXE_NAME;

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
    $opt{quiet} or _log( q{-}, @_ );
}

# ------------------------------------------------------------------------------
sub _d
{
    $opt{debug} and _log( q{*}, @_ );
}

# ------------------------------------------------------------------------------
