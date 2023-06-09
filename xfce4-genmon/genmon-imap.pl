#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Config::Find;
use Config::Std;
use Const::Fast;
use Encode qw/decode_utf8/;
use Encode::IMAPUTF7;
use English qw/-no_match_vars/;
use File::Basename;
use File::Spec;
use List::MoreUtils qw/none/;
use Mail::IMAPClient;
use Path::ExpandTilde;
use Try::Tiny;

# ------------------------------------------------------------------------------
our $VERSION = 'v1.0';
const my $EXE_NAME    => basename $PROGRAM_NAME;
const my $EXE_DIR     => File::Spec->rel2abs( dirname $PROGRAM_NAME);
const my $CONFIG_NAME => $EXE_NAME =~ /^(.*)[.][^.]+$/ms ? $1 : $EXE_NAME;
const my $TPL         => '<click>%s &> /dev/null</click><img>%s</img><tool>%s</tool>';

# ------------------------------------------------------------------------------
_usage() if $ARGV[0] && ( $ARGV[0] eq '-h' || $ARGV[0] eq '--help' );

my $cfg = _load_config();
my %data;
while ( my ( $section, $imap ) = each %{$cfg} ) {
    next if $section eq q{_};
    $data{$section} = _check_mailboxes($imap);
}

my $total   = 0;
my $tooltip = q{};

for ( sort keys %data ) {
    my $mailboxes = $data{$_};
    $tooltip .= sprintf "┌ <span fgcolor='blue' weight='bold'>%s</span>\n", $_;

    if ( $mailboxes->{_} ) {
        $tooltip .= sprintf "└─ <span fgcolor='red'>%s</span>\n", _trim( $mailboxes->{_} );
        next;
    }

    my @mkeys = sort keys %{$mailboxes};
    while (@mkeys) {
        my $mbox   = shift @mkeys;
        my $tchar  = @mkeys > 0 ? '├─' : '└─';
        my $unseen = $mailboxes->{$mbox};
        if ( $unseen =~ /^\d+$/sm ) {
            if ($unseen) {
                $total += $unseen;
                $tooltip .= sprintf "%s <span fgcolor='green'>%s : %u</span>\n", $tchar, $mbox, $unseen;
            }
            else {
                $tooltip .= sprintf "%s %s : 0\n", $tchar, $mbox;
            }
        }
        else {
            $tooltip .= sprintf "%s %s : <span fgcolor='red'>%s</span>\n", $tchar, $mbox, _trim($unseen);
        }
    }
}

#<<V
printf $TPL,
    $cfg->{_}->{click},
    $total ? $cfg->{_}->{new} : $cfg->{_}->{nonew},
    $tooltip
    ;
#>>V
# ------------------------------------------------------------------------------
sub _load_config
{
    my $configfile = $ARGV[0] ? $ARGV[0] : Config::Find->find;
    _usage() unless ($configfile);
    my %config;
    try {
        read_config expand_tilde($configfile) => %config;
    }
    catch {
        printf "%s\n", _trim($_);
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
    $config{_}->{click} //= 'true';
    _values_to_scalar( $config{_}, q{new}, q{nonew}, q{click}, q{offline} );
    if ( $config{_}->{offline} ) {
        $config{$_}->{offline} = 1 for keys %config;
    }
    _check_icon( \%config, q{new} );
    _check_icon( \%config, q{nonew} );
    return \%config;
}

# ------------------------------------------------------------------------------
sub _values_to_scalar
{
    my ( $hash, @keys ) = @_;

    while ( my ( $key, $value ) = each %{$hash} ) {
        next if none { $_ eq $key } @keys;
        if ( ref $value eq 'ARRAY' ) {
            $hash->{$key} = pop @{$value};
        }
    }
    return $hash;
}

# ------------------------------------------------------------------------------
sub _trim
{
    $_[0] =~ s/^\s+|\s+$//gsm;
    return $_[0];
}

#------------------------------------------------------------------------------
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
sub _check_mailboxes
{
    my ($section) = @_;

    my %mailboxes;

    if ( $section->{offline} ) {
        $mailboxes{_} = 'offline';
        return \%mailboxes;
    }

    my $imap = Mail::IMAPClient->new(
        Server   => $section->{host},
        User     => $section->{user},
        Password => $section->{password},
        debug    => 0,
        ssl      => 1,
    );
    if ( !$imap ) {
        $mailboxes{_} = $EVAL_ERROR;
        return \%mailboxes;
    }

    my $folders = $imap->folders;
    $_ = Encode::IMAPUTF7::decode( 'IMAP-UTF-7', $_ ) for @{$folders};
    for ( @{ $section->{mailbox} } ) {
        my $box = decode_utf8($_);
        my $unseen;
        if ( none { $_ eq $box } @{$folders} ) {
            $unseen = 'invalid mailbox';
        }
        else {
            $unseen = $imap->unseen_count( Encode::IMAPUTF7::encode( 'IMAP-UTF-7', $box ) ) // 0;
            my $error = $imap->LastError;
            $error and $unseen = $error;
        }
        $mailboxes{$box} = $unseen;
    }
    $imap->logout;
    return \%mailboxes;
}

# ------------------------------------------------------------------------------
sub _check_icon
{
    my ( $config, $icon ) = @_;

    # 1) No icon, test default files:
    if ( !$config->{_}->{$icon} ) {
        $config->{_}->{$icon} = sprintf '%s/.config/%s/%s.png', $ENV{HOME}, $CONFIG_NAME, $icon;
        $config->{_}->{$icon} = sprintf '%s/%s/%s.png', $EXE_DIR, $CONFIG_NAME, $icon
            unless -f $config->{_}->{$icon};
    }

    # 2) File name only, test default locations:
    elsif ( $config->{_}->{$icon} !~ /\//sm ) {
        my $iconame = $config->{_}->{$icon};
        $config->{_}->{$icon} = sprintf '%s/.config/%s/%s', $ENV{HOME}, $CONFIG_NAME, $iconame;
        $config->{_}->{$icon} = sprintf '%s/%s/%s', $EXE_DIR, $CONFIG_NAME, $iconame
            unless -f $config->{_}->{$icon};
    }

    $config->{_}->{$icon} = expand_tilde $config->{_}->{$icon};

    if ( !-f $config->{_}->{$icon} ) {
        printf "Can not find icon '%s'\n", $config->{_}->{$icon};
        _help();
    }
    return $config;
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
    _help( $section, 'Mailbox' ) unless @{ $content->{mailbox} };

    _values_to_scalar( $content, q{host}, q{user}, q{password} );

    return $content;
}

# ------------------------------------------------------------------------------
sub _usage
{
    my ($help) = @_;

    CORE::state $USAGE = <<'USAGE';
Usage: %s [config_file]

If no configuration file is specified on the command line, the first one found will be used (extension can be .conf or .cfg):
    ~/.%s
    ~/.%s.conf
    %s/../etc/%s.conf
    %s/../conf/%s.conf
    /etc/%s.conf
USAGE
#<<V    
    printf $USAGE,

    $EXE_NAME,

    $CONFIG_NAME,
    $CONFIG_NAME,
    $EXE_DIR, $CONFIG_NAME,
    $EXE_DIR, $CONFIG_NAME,
    $CONFIG_NAME
    ;
#>>V
    return _help();
}

# ------------------------------------------------------------------------------
sub _help
{
    my ( $section, $value ) = @_;

    CORE::state $HELP = <<'HELP';

Valid config format:
    # Click is optional. 
    # NB! With "birdtray" use 'Click = birdtray -s' 
    Click = /usr/bin/thunderbird
    # Offline for ALL sections:
    Offline = 1
    New   = /path/to/icon
    NoNew = /path/to/icon
    # If New/NoNew empty, then the following icons will be used:
    #   ~/.config/%s/new.png 
    #   %s/%s/new.png 
    #   ~/.config/%s/nonew.png
    #   %s/%s/nonew.png 
    #
    # Without path icons will be searched in the same directories:
    # New = google-new.png
    #   => ~/.config/%s/google-new.png 
    #   => %s/%s/google-new.png 

    [Unique Name]
      Host     = IP:PORT
      User     = USER
      Password = PASSWORD
      Mailbox  = INBOX
      Mailbox  = Job
      Mailbox  = Friends
      #...
      # Offline = 1
HELP

    printf "Invalid '%s' key in section [%s]\n", $value, $section if $section;
#<<V    
    printf $HELP,

        $CONFIG_NAME,
        $EXE_DIR, $CONFIG_NAME,
        $CONFIG_NAME,
        $EXE_DIR, $CONFIG_NAME,

        $CONFIG_NAME,
        $EXE_DIR, $CONFIG_NAME,
        ;
#>>V
    exit 1;
}

# ------------------------------------------------------------------------------
