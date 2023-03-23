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
    if ( $section =~ /^icon$/ism ) {
        if ( $section ne 'icon' ) {
            $config{icon} = $config{$section};
            delete $config{$section};
        }
    }
    else {
        _check_imap_section( \%config, $section );
    }
}
if ( !$config{icon}->{'new'} || !-f $config{icon}->{'new'} ) {
    say 'Can not find "New" icon.';
    _help();
}
if ( !$config{icon}->{'nonew'} || !-f $config{icon}->{'nonew'} ) {
    say 'Can not find "NoNew" icon.';
    _help();
}

my %data;
while ( my ( $section, $content ) = each %config ) {

    #    $data{$section} = _check_mailboxes($content);
}

# ------------------------------------------------------------------------------
sub _check_imap_section
{
    my ( $config, $section ) = @_;
    my $content = $config->{$section};
    for ( keys %{$content} ) {
        if ( !/^[[:lower:]]+$/sm ) {
            $content->{ lc() } = $content->{$_};
            delete $content->{$_};
        }
    }
    _help( $section, 'Host' )     unless $content->{host};
    _help( $section, 'User' )     unless $content->{user};
    _help( $section, 'Password' ) unless $content->{password};
    _help( $section, 'Click' )    unless $content->{click};
    _help( $section, 'Mailbox' )  unless $content->{mailbox};
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
    my ( $section, $value ) = @_;
    printf "No '%s' in section [%s]\n", $value, $section if $section;
    say <<'HELP';

Valid [Icon] section, all fields are required:
    New = /path/to/icon
    NoNew = /path/to/icon

Valid IMAP sections, all fields are required:
    [Unique Name]
    Host = IP:PORT
    User = USER
    Password = PASSWORD
    Mailbox = INBOX
    ; There may be several Mailbox fields:
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
