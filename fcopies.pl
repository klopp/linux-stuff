#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;

# ------------------------------------------------------------------------------
use Capture::Tiny qw/capture_stderr/;
use English qw/-no_match_vars/;
use File::Basename qw/basename/;
use Getopt::Long qw/GetOptions/;
use Path::Iterator::Rule;
use Path::Tiny;

our $VERSION = 'v1.00';

# ------------------------------------------------------------------------------
my ( $file_md5, $find_file, $follow_symlinks, $quiet, @paths );
GetOptions( 'p=s' => \@paths, 'f=s' => \$find_file, 'h|?' => \&_usage, q{s} => \$follow_symlinks, q{q} => \$quiet );
( @paths > 0 and $find_file ) or _usage();
my $file_path = path($find_file);
if ( !$file_path->exists ) {
    printf "Can not find file \"%s\".\n", $find_file;
    exit 2;
}
my $file_digest = $file_path->digest;
my $rule        = Path::Iterator::Rule->new;
$rule->file->size( $file_path->size );
$rule->and(
    sub {
        return path( $_[0] )->digest eq $file_digest;
    }
);

if ($quiet) {
    capture_stderr \&_find;
}
else {
    _find();
}

# ------------------------------------------------------------------------------
sub _find
{
    for my $file ( $rule->all( @paths, { error_handler => undef, follow_symlinks => $follow_symlinks } ) ) {
        printf "%s\n", $file;
    }
}

# ------------------------------------------------------------------------------
sub _usage
{
    CORE::state $USAGE = <<'USAGE';

Search for copies of the specified file (-f) in paths (-p, there may be several).
Print errors if the -q switch is not specified.
Symbolic link processing is disabled by default, use the -s switch to enable it.
 
Usage: %s -p PATH [-p PATH ...] -f FILE [-s] [-q]

USAGE
    printf $USAGE, basename($PROGRAM_NAME);
    exit 1;
}

# ------------------------------------------------------------------------------
