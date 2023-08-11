#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;

# ------------------------------------------------------------------------------
use Capture::Tiny qw/capture_stderr/;
use Const::Fast;
use English qw/-no_match_vars/;
use File::Basename qw/basename/;
use Getopt::Long qw/GetOptions/;
use Path::Iterator::Rule;
use Path::Tiny;

our $VERSION = 'v1.00';

# ------------------------------------------------------------------------------
my ( $dtype, @paths, $file, $namematch, $quiet ) = ('MD5');
my %ropts = ( sorted => 0, error_handler => undef, follow_symlinks => undef );
GetOptions(
    'p=s' => \@paths,
    'd=s' => \$dtype,
    'f=s' => \$file,
    'h|?' => \&_usage,
    q{s}  => \$ropts{follow_symlinks},
    q{n}  => \$namematch,
    q{q}  => \$quiet,
);

$file or _usage();
if ( !-f $file ) {
    printf "Not regular file: \"%s\".\n", $file;
    exit 2;
}
my $npaths = scalar @paths;
for (@paths) {
    -d or --$npaths;
}
if ( !$npaths ) {
    print "No valid paths found.\n";
    exit 3;
}

my $path = path($file);
my $rule = Path::Iterator::Rule->new;
if ($namematch) {
    $rule->name( $path->basename );
}
else {
    my $digest = $path->digest($dtype);
    $rule->file->size( $path->size );
    $rule->and(
        sub {
            return path( $_[0] )->digest($dtype) eq $digest;
        }
    );
}

if ($quiet) {
    capture_stderr \&_search;
}
else {
    _search();
}

# ------------------------------------------------------------------------------
sub _search
{
    printf "%s\n", $_ for $rule->all_fast( @paths, \%ropts );
}

# ------------------------------------------------------------------------------
sub _usage
{
    CORE::state $USAGE = <<'USAGE';

Usage: %s -p PATH [-p PATH ...] -f FILE [-s] [-q] [-n] -d DIGEST]

Search for copies of the specified file (-f) in paths (-p).
Print errors if the -q switch is not specified.
Symbolic link processing is disabled by default, use the -s switch to enable it.
Default file digest is 'MD5', set it by -d key (see https://metacpan.org/pod/Digest).
Match only base name of file if -n key is specified.
 
USAGE
    printf $USAGE, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
