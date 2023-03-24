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
use Encode qw/decode_utf8/;
use Encode::IMAPUTF7;
use English qw/-no_match_vars/;
use File::Basename;
use File::Spec;
use Mail::IMAPClient;
use Try::Tiny;

use DDP;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.0';
const my $EXE_NAME    => basename $PROGRAM_NAME;
const my $EXE_DIR     => File::Spec->rel2abs( dirname $PROGRAM_NAME);
const my $CONFIG_NAME => $EXE_NAME =~ /^(.*)[.][^.]+$/ms ? $1 : $EXE_NAME;
const my $TPL         => <<'TPL';
<click>%s &> /dev/null</click><img>%s</img>
<tool>%s</tool>
TPL

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
while ( my ( $section, $config ) = each %config ) {
    next if $section eq q{_};
    $data{$section} = _check_mailboxes($config);
}

my $total   = 0;
my $tooltip = '';

while ( my ( $imap, $mailboxes ) = each %data ) {
    $tooltip .= "<span fgcolor='blue' weight='bold'>$imap</span>\n";

    if ( $mailboxes->{_} ) {
        $tooltip .= '  <span fgcolor="red">' . $mailboxes->{_} . "</span>\n";
        next;
    }

    while ( my ( $mailbox, $unseen ) = each %{$mailboxes} ) {
        $tooltip .= "  $mailbox : ";
        if ( $unseen =~ /^\d+$/ ) {
            if ($unseen) {
                $total += $unseen;
                $tooltip .= "<span weight='bold' fgcolor='green'>$unseen</span>\n";
            }
            else {
                $tooltip .= "$unseen\n";
            }
        }
        else {
            $tooltip .= "<span fgcolor='red'>$unseen</span>\n";
        }
    }
}

printf $TPL, $config{_}->{click}, $total ? $config{_}->{'new'} : $config{_}->{'nonew'}, $tooltip;

# ------------------------------------------------------------------------------
sub _check_mailboxes
{
    my ($config) = @_;

    my %mailboxes;
    my $total = 0;
    my $imap  = Mail::IMAPClient->new(
        Server   => $config->{host},
        User     => $config->{user},
        Password => $config->{password},
        debug    => 0,
        ssl      => 1,
    );
    if ( !$imap ) {
        $mailboxes{_} = $@;
        return \%mailboxes;
    }

    for ( @{ $config->{mailbox} } ) {
        my $box    = decode_utf8($_);
        my $unseen = $imap->unseen_count( Encode::IMAPUTF7::encode( 'IMAP-UTF-7', $box ) ) // 0;
        my $error  = $imap->LastError;
        if ($error) {
            $mailboxes{$box} = $error;
        }
        else {
            $mailboxes{$box} = $unseen;
        }
    }
    $imap->logout;
    return \%mailboxes;
}

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

# ------------------------------------------------------------------------------
sub _usage
{
    my ($help) = @_;

    my $USAGE = q{
Usage: %s [config_file]

If no configuration file is specified on the command line, the first one found will be used (extension can be .conf or .cfg):
    ~/.%s
    ~/.%s.conf
    %s/../etc/%s.conf
    %s/../conf/%s.conf
    /etc/%s.conf
};

    printf $USAGE, $EXE_NAME, $CONFIG_NAME, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME, $CONFIG_NAME;
    return _help();
}

# ------------------------------------------------------------------------------
sub _help
{
    my ( $section, $value ) = @_;

    my $HELP = q{
Valid config format:

    # If New/NoNew empty, then the following icons will be used:
    # ~/.config/%s/new.png 
    # ~/.config/%s/nonew.png
    # or
    # %s/%s/new.png 
    # %s/%s/nonew.png 
    New = /path/to/icon
    NoNew = /path/to/icon

    # Optional. 
    Click = /usr/bin/thunderbird
    
    [Unique Name]
        Host = IP:PORT
        User = USER
        Password = PASSWORD
        Mailbox = INBOX
        ; There may be several Mailbox fields:
        Mailbox = Job
        Mailbox = Friends
        $...
};

    printf "No '%s' in section [%s]\n", $value, $section if $section;
    printf $HELP, $CONFIG_NAME, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME, $EXE_DIR, $CONFIG_NAME;
    exit 1;
}

# ------------------------------------------------------------------------------
