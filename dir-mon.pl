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
use IPC::Run qw/run/;
use POSIX qw/:sys_wait_h strftime/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;
use Time::Local qw/timelocal_posix/;

# ------------------------------------------------------------------------------
const my $INTERVAL => 30;
const my $INOTYFY  => 'inotifywait';
const my $RX_DATE  => '(\d{4})[-](\d\d)[-](\d\d)';
const my $RX_TIME  => '(\d\d):(\d\d):(\d\d)';
our $VERSION = 'v1.01';

# ------------------------------------------------------------------------------
my ( $last_access, $ipid );
my ( $TIMEOUT, $PATH, $EXEC, $QUIET, $DEBUG, $EXIT, $DRY ) = ( 60 * 10 );

my $inotifywait = which $INOTYFY;
if ( !$inotifywait ) {
    print "No required '$INOTYFY' executable found!\n";
    exit 1;
}

# ------------------------------------------------------------------------------
GetOptions(
    'p|path=s'    => \$PATH,
    't|timeout=i' => \$TIMEOUT,
    'e|exec=s'    => \$EXEC,
    'dry-run'     => \$DRY,
    'x|exit'      => \$EXIT,
    'q|quiet'     => \$QUIET,
    'd|debug'     => \$DEBUG,
    'h|?|help'    => \&_usage,
);
( $EXEC && $PATH && -d $PATH && $TIMEOUT && $TIMEOUT =~ /^\d+$/sm ) or _usage();

my @EXECUTABLE = quotewords( '\s+', 1, $EXEC );
for (@EXECUTABLE) {
    s/__PATH__/"$PATH"/gsm;
    s/__HOME__/$ENV{HOME}/gsm;
}

my $cpid = fork;
exit if $cpid;
$cpid = fork;
exit if $cpid;

# ------------------------------------------------------------------------------
local $SIG{ALRM} = \&_check_access_time;
local $SIG{TERM} = \&_term;
local $SIG{QUIT} = \&_term;
local $SIG{USR1} = \&_term;
local $SIG{USR1} = \&_term;
local $SIG{HUP}  = \&_term;
local $SIG{INT}  = \&_term;
$last_access = time;
alarm $INTERVAL;

my $icmd = sprintf '%s -q -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"', $inotifywait, $PATH;
_d( 'Run %s...', $icmd );
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
        _i( 'No activity for %u sec', $tdiff );
        if ( $tdiff >= $TIMEOUT ) {
            _i('Timeout!');
            ( $DEBUG or $DRY ) and _log( "{run}\n> %s", ( join "\n> ", @EXECUTABLE ) );
            my ( $out, $err );
            $DRY or run \@EXECUTABLE, sub { }, \$out, \$err;
            $out  and _log( '%s', _trim($out) );
            $err  and _log( '%s', _trim($err) );
            $EXIT and _term();

            #            kill HUP => $ipid;
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

   -?, -h, -help      this message
   -p, -path    PATH  directory to watch (required, see *)
   -t, -timeout SEC   activity timeout (seconds, default: %u)
   -e, -exec    PATH  execute on activity timeout (required, see *)
   -q, -quiet         be quiet
   -d, -debug         print debug info
   -dry-run           do not run executable, print command line only
   -x, -exit          exit after execute (default: reset timeout)

WARNING! 
Always use -x key if the directory will be unmounted by executable call.

   *
        __PATH__ substring will be rplaced by "-p" value
        __HOME__ substring will be rplaced by $HOME value

Example:

    %s -x -q -dry-run -t 300 -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__"

USAGE
    printf $USAGE, basename($PROGRAM_NAME), $TIMEOUT, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
sub _term
{
    if ($ipid) {
        killfam 'TERM', ($ipid);
        while ( ( my $kidpid = waitpid -1, WNOHANG ) > 0 ) {
            sleep 1;
        }
    }
    exit;
}

# ------------------------------------------------------------------------------
END {
    _term();
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
    my ( $fmt, @arg ) = @_;
    return printf "%s %s\n", _t(), sprintf $fmt, @arg;
}

# ------------------------------------------------------------------------------
sub _i
{
    $QUIET or _log(@_);
}

# ------------------------------------------------------------------------------
sub _d
{
    $DEBUG and _log(@_);
}

# ------------------------------------------------------------------------------
