#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Carp qw/carp confess/;
use Config::Find;
use Config::Std;
use Encode::IMAPUTF7;
use English qw/-no_match_vars/;
use File::Basename;
use Mail::IMAPClient;
use Try::Tiny;

use DDP;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.0';

# ------------------------------------------------------------------------------
my $configfile = $ARGV[0] ? $ARGV[0] : Config::Find->find;
_usage() unless ($configfile);
my %config;
try {
    read_config $configfile => %config;
}
catch {
    carp $_;
    _help();
};

while ( my ($section) = each %config ) {
    _check_config_section( \%config, $section );
}

p %config;

# ------------------------------------------------------------------------------
sub _check_config_section
{
    my ( $config, $section ) = @_;
    my $content = $config->{$section};
    for ( keys %{$content} ) {
        if ( !/^[[:lower:]]$/sm ) {
            $content->{lc} = $content->{$_};
            delete $content->{$_};
        }
    }
    if ( !$content->{host} || !$content->{user} || !$content->{password} || !$content->{mailbox} ) {
        _help();
    }
    $content->{mailbox} = [ $content->{mailbox} ]
        unless ref $content->{mailbox} eq 'ARRAY';
    return $content;
}

# ------------------------------------------------------------------------------
sub _usage
{
    my ($help) = @_;
    my $pname  = basename $PROGRAM_NAME;
    my $cname  = $pname;
    $cname =~ s/[.][^.]*$//sm;
    my $cdir  = dirname $PROGRAM_NAME;
    my $usage = <<'USAGE';
Usage: %s [config_file]

If the configuration file is not specified on the command line, it will be searched in:
    ~/.%s
    ~/.%s.conf
    %s/../etc/%s.conf
    %s/../conf/%s.conf
    /etc/%s.conf
USAGE
    printf $usage, $pname, $cname, $cname, $cdir, $cname, $cdir, $cname, $cname,;
    return _help();
}

# ------------------------------------------------------------------------------
sub _help
{
    say <<'HELP';

Valid config file:
    [Unique Name]
    Host = IP:PORT
    User = USER
    Password = PASSWORD
    Mailbox = INBOX
    Mailbox = Job
    Mailbox = Friends
    ...
Valid comments at line start:
    ; comment
    # comment    
    - comment    

HELP
    exit 1;
}

# ------------------------------------------------------------------------------
