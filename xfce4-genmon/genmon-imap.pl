#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Carp qw/carp/;
use Config::Find;
use Config::Std;
use Const::Fast;
use Encode::IMAPUTF7;
use English qw/-no_match_vars/;
use File::Basename;
use Mail::IMAPClient;
use Try::Tiny;

use DDP;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.0';
const my $EXE_NAME    => basename $PROGRAM_NAME;
const my $EXE_DIR     => dirname $PROGRAM_NAME;
const my $CONFIG_NAME => $EXE_NAME =~ /^(.*)[.][^.]+$/ms ? $1 : $EXE_NAME;

# ------------------------------------------------------------------------------
_usage() if $ARGV[0] && ( $ARGV[0] eq '-h' || $ARGV[0] eq '--help' );
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

p %config;

for ( keys %config ) {
    if ($_) {
        _check_imap_section( \%config, $_ );
    }
    else {
        $config{_} = $config{$_};
        _lower_keys( $config{_} );
        delete $config{$_};
    }
}
_check_icon( \%config, 'new' );
_check_icon( \%config, 'nonew' );
$config{_}->{click} //= 'true';

my %data;
while ( my ( $section, $content ) = each %config ) {

    #    $data{$section} = _check_mailboxes($content);
}

my $tpl = <<'TPL';
<click>%s &> /dev/null</click><img>%s</img>
<tool>%s</tool>
TPL

printf $tpl, $config{_}->{click},
    $data{unseen} ? $config{_}->{'new'} : $config{_}->{'nonew'},
    '?';

# ------------------------------------------------------------------------------
sub _check_icon
{
    my ( $config, $icon ) = @_;
    $config->{_}->{$icon} //= sprintf '~/.config/%s/%s.png', $CONFIG_NAME, $icon;

    if ( !-f $config->{_}->{$icon} ) {
        printf "Can not find icon '%s'\n", $config->{_}->{$icon};
        _help();
    }
    return $config;
}

# ------------------------------------------------------------------------------
sub _lower_keys
{
    my ($hash) = @_;
    for ( keys %{$hash} ) {
        if ( !/^[[:lower:]]+$/sm ) {
            $hash->{ lc() } = $hash->{$_};
            delete $hash->{$_};
        }
    }
    return $hash;
}

# ------------------------------------------------------------------------------
sub _check_imap_section
{
    my ( $config, $section ) = @_;
    my $content = $config->{$section};
    _lower_keys($content);
    _help( $section, 'Host' )     unless $content->{host};
    _help( $section, 'User' )     unless $content->{user};
    _help( $section, 'Password' ) unless $content->{password};
    _help( $section, 'Mailbox' )  unless $content->{mailbox};
    $content->{mailbox} = [ $content->{mailbox} ]
        unless ref $content->{mailbox} eq 'ARRAY';
    return $content;
}

# ------------------------------------------------------------------------------
sub _usage
{
    my ($help) = @_;
    my $usage = <<'USAGE';
Usage: %s [config_file]

If no configuration file is specified on the command line, the first one found will be used:
    ~/.%s
    ~/.%s.conf
    %s/../etc/%s.conf
    %s/../conf/%s.conf
    /etc/%s.conf
USAGE
    printf $usage, $EXE_NAME, $CONFIG_NAME, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME, $CONFIG_NAME;
    return _help();
}

# ------------------------------------------------------------------------------
sub _help
{
    my ( $section, $value ) = @_;
    printf "No '%s' in section [%s]\n", $value, $section if $section;
    my $help = <<'HELP';

Valid config format:

    # If New/NoNew empty, then the following icons will be used:
    # ~/.config/%s/new.png 
    # ~/.config/%s/nonew.png 
    New = /path/to/icon
    NoNew = /path/to/icon

    # Optional 
    Click = /usr/bin/thunderbird
    
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
    $ comment    

HELP
    printf $help, $CONFIG_NAME, $CONFIG_NAME;
    exit 1;
}

# ------------------------------------------------------------------------------
