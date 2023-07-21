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
my ( $dtype, @paths, $file, $algo, $quiet ) = ('MD5');
my %ropts = ( error_handler => undef, follow_symlinks => undef );
GetOptions(
    'p=s' => \@paths,
    'd=s' => \$dtype,
    'f=s' => \$file,
    'h|?' => \&_usage,
    q{a}  => \$algo,
    q{s}  => \$ropts{follow_symlinks},
    q{q}  => \$quiet,
);
( @paths > 0 and $file ) or _usage();
my $path = path($file);
if ( !$path->exists ) {
    printf "Can not find file \"%s\".\n", $file;
    exit 2;
}
my $digest = $path->digest($dtype);
my $rule   = Path::Iterator::Rule->new;
$rule->file->size( $path->size );
$rule->and(
    sub {
        return path( $_[0] )->digest($dtype) eq $digest;
    }
);

if ($quiet) {
    capture_stderr \&_search;
}
else {
    _search();
}

# ------------------------------------------------------------------------------
sub _search
{
    printf "%s\n", $_ for $algo ? $rule->all( @paths, \%ropts ) : $rule->all_fast( @paths, \%ropts );
}

# ------------------------------------------------------------------------------
sub _usage
{
    CORE::state $USAGE = <<'USAGE';

Usage: %s -p PATH [-p PATH ...] -f FILE [-s] [-q] [-a] [-d DIGEST]

Search for copies of the specified file (-f) in paths (-p).
Print errors if the -q switch is not specified.
Symbolic link processing is disabled by default, use the -s switch to enable it.
Use the alternative search algorithm by -a key.
Default file digest id \MD5', set it by -d key.
 
USAGE
    printf $USAGE, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
