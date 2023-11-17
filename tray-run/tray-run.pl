#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;
use utf8::all;
use open qw/:std :utf8/;

use Const::Fast;
use English qw/-no_match_vars/;
use File::Basename qw/dirname/;
use Gtk3 qw/-init/;
use IPC::Run qw/run/;
use POSIX qw/:sys_wait_h/;
use Proc::Killfam;
use Text::ParseWords qw/quotewords/;
use Try::Catch;

use Things::Bool;
use Things::Config::Std;

# ------------------------------------------------------------------------------
const my $DEF_KILL => 'TERM';
const my $ICO_PATH => dirname($PROGRAM_NAME) . q{/};

# ------------------------------------------------------------------------------
our $VERSION = '1.0';

# ------------------------------------------------------------------------------
my $pid;
my $config = $ARGV[0] || q{*};
my $cfg    = Things::Config::Std->new( file => $config, nocase => 1 );
$cfg->error and Carp::croak sprintf 'FATAL :: %s', $cfg->error;
my $exec  = _cget('Exec');
my $kill  = $cfg->get('kill');
my $on    = _icon('On');
my $off   = _icon('Off');
my $state = parse_bool( _cget('Active') ) ? 0 : 1;

$exec =~ s/^~/$ENV{HOME}/sm;
-x $exec or Carp::croak sprintf '"%s" is not executable file', $exec;
if ( !$kill ) {
    $kill = $DEF_KILL;
    Carp::carp sprintf 'CONFIG :: no "Kill", set to "%s"', $DEF_KILL;
}
exists $SIG{$kill} or Carp::croak 'CONFIG :: invalid "Kill" value';

my $trayicon = Gtk3::StatusIcon->new;
_switch_state();
$trayicon->set_tooltip_text("Left click: execute/stop\nRight click: stop and exit");
$trayicon->signal_connect(
    'button_press_event' => sub {
        my ( undef, $event ) = @_;
        if ( $event->button eq 3 ) {
            _stop();
            Gtk3->main_quit;
        }
        elsif ( $event->button eq 1 ) {
            _switch_state();
        }
        1;
    }
);

Gtk3->main;

# ------------------------------------------------------------------------------
sub _cget
{
    my ($name) = @_;
    my $val = $cfg->get( lc $name );
    $val or Carp::croak sprintf 'CONFIG :: no "%s" value', $name;
    return $val;
}

# ------------------------------------------------------------------------------
sub _icon
{
    my ($name) = @_;
    my ( $file, $ico ) = ( _cget($name) );

    try {
        $file = $ICO_PATH . $file;
        $ico  = Gtk3::Gdk::Pixbuf->new_from_file($file);
    }
    catch {
        Carp::croak sprintf 'Can not create icon from file "%s" (%s)', $file, $_;
    };
    return $ico;
}

# ------------------------------------------------------------------------------
sub _stop
{
    $pid and killfam $kill, $pid;
}

# ------------------------------------------------------------------------------
sub _start
{
    $pid = fork();
    if ( !defined $pid ) {
        Carp::croak sprintf 'Fork error :: %s', $ERRNO;
    }
    elsif ( !$pid ) {
        try {
            run [ quotewords( '\s+', 1, $exec ) ], sub { }, sub { }, sub { };
        }
        catch {
            Carp::carp sprintf '[%s] :: %s', $exec, $_;
        };
    }
    else {
        local $SIG{CHLD} = sub {
            1 while waitpid( $pid, WNOHANG ) > 0;
            undef $pid;
        }
    }
}

# ------------------------------------------------------------------------------
sub _switch_state
{
    if ($state) {
        $trayicon->set_from_pixbuf($off);
        _stop();
    }
    else {
        $trayicon->set_from_pixbuf($on);
        _start();
    }
    $state ^= 1;
}

# ------------------------------------------------------------------------------
END {
    _stop();
}

# ------------------------------------------------------------------------------
__END__
