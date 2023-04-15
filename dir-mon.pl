#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Const::Fast;
use English qw/-no_match_vars/;
use File::Basename qw/basename/;
use File::Which;
use Getopt::Long qw/GetOptions/;
use IPC::Open2;
use IPC::Run qw/run/;
use POSIX qw/:sys_wait_h/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;
use Time::Local qw/timelocal_posix/;

# ------------------------------------------------------------------------------
const my $INTERVAL => 30;
const my $INOTYFY  => 'inotifywait';
our $VERSION = 'v1.01';

# ------------------------------------------------------------------------------
my ( $last_access, $ipid );
my ( $TIMEOUT, $PATH, $EXEC, $QUIET, $DEBUG, $EXIT, $DRY ) = ( 60 * 10 );

my $inotifywait = which $INOTYFY;
if ( !$inotifywait ) {
    say "\nNo required '$INOTYFY' executable found!";
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

$ipid = open2( my $stdout, undef, sprintf '%s -q -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"',
    $inotifywait, $PATH );

while (<$stdout>) {

    next unless m{^
        (\d{4})[-](\d\d)[-](\d\d)
        \s+
        (\d\d):(\d\d):(\d\d)
        \s+
        (.*)
        \s+
        \[(.+)\]
    }xsm;

    my $taccess = timelocal_posix( $6, $5, $4, $3, $2 - 1, $1 - 1900 );
    $DEBUG and printf "[%04d-%02d-%02d %02d:%02d:%02d] %s {%s}\n", $1, $2, $3, $4, $5, $6, $7, $8;
    _check_access_time( undef, $taccess );
}

# ------------------------------------------------------------------------------
sub _check_access_time
{
    my ( undef, $taccess ) = @_;

    my $tdiff = $taccess ? $taccess - $last_access : time - $last_access;
    if ( $tdiff > 0 ) {
        $QUIET or printf "No activity: %u sec\n", $tdiff;
        if ( $tdiff >= $TIMEOUT ) {
            $QUIET or print "Timeout!\n";
            ( $DEBUG or $DRY ) and printf "{run}\n> %s\n", ( join "\n> ", @EXECUTABLE );
            my ( $out, $err );
            $DRY or run \@EXECUTABLE, sub { }, \$out, \$err;
            $out  and print $out;
            $err  and print $err;
            $EXIT and _term();
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

Run example:

    %s -x -q -dry-run -t 300 -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__"

umount.sh example:

    #!/bin/bash
    LSOF=$(lsof "$1" | awk 'NR>1 {print $2}' | sort -n | uniq)
    if [[ -z "$LSOF" ]]; then
        sudo umount -l "$1"
    else
        echo -e "\nDirectory $1 used by:\n\n$(ps --no-headers -o command -p ${LSOF})"
    fi

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
