#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Capture::Tiny qw/capture_stderr/;
use English qw/-no_match_vars/;
use File::Basename qw/basename/;
use Getopt::Long qw/GetOptions/;
use IPC::Open2;
use IPC::Run qw/run/;
use Text::ParseWords qw/quotewords/;
use Time::Local qw/timelocal_posix/;
use POSIX qw/strftime/;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.0';
my ( $last_access, $pid, $stdout );
my ( $TIMEOUT, $PATH, $EXEC, $QUIET, $DEBUG, $EXIT, $DRY ) = ( 60 * 10 );

#my $taccess = timelocal_posix( 0, 1, 13, 15, 4, 2023 );
#say strftime( '%R:%S', localtime $taccess );
#exit;

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

# ------------------------------------------------------------------------------
capture_stderr {
    $pid
        = open2( $stdout, undef,
        sprintf 'inotifywait -m -r --timefmt="%%Y-%%m-%%d %%X" --format="%%T %%w%%f [%%e]" "%s"', $PATH );
};

local $SIG{ALRM} = \&_check_access_time;
$last_access = time;
alarm 60;

while (<$stdout>) {

    next unless /^(\d{4})[-](\d\d)[-](\d\d) (\d\d):(\d\d):(\d\d)\s+(.+)\s+\[(.+)\]/sm;

    my $taccess = timelocal_posix( $6, $5, $4, $3, $2 - 1, $1 - 1900 );
    $DEBUG and printf "[%04d-%02d-%02d %02d:%02d:%02d] %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8;
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
            my @eparts = quotewords( '\s+', 1, $EXEC );
            $_ =~ s/__PATH__/"$PATH"/gsm    for @eparts;
            $_ =~ s/__HOME__/$ENV{HOME}/gsm for @eparts;
            ( $DEBUG or $DRY ) and printf "{run}\n> %s\n", ( join "\n> ", @eparts );
            $DRY or run \@eparts, sub { }, sub { }, sub { };
            $EXIT and exit;
            $last_access = time;
        }
        else {
            $taccess and $last_access = $taccess;
        }
    }
    alarm 60;
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

   *
        __PATH__ substring will be rplaced by "-p" value
        __HOME__ substring will be rplaced by $HOME value

Example:

    %s -q -dry-run -t 300 -p "__HOME__/nfs" -e "__HOME__/bin/umount.sh __PATH__"
    
USAGE
    printf $USAGE, basename($PROGRAM_NAME), $TIMEOUT, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
END {
    $pid and waitpid( $pid, 0 );
}

# ------------------------------------------------------------------------------
