#!/usr/bin/perl

# ------------------------------------------------------------------------------
use 5.014;
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Const::Fast;
use File::Basename q/fileparse/;
use File::ChangeNotify;
use File::Path qw/make_path/;
use forks;
use forks::shared;
use IPC::Run qw/run/;
use Log::Any qw/$log/;
use Log::Any::Adapter;
use Thread::Queue;

# ------------------------------------------------------------------------------
const my $THREADS => 4;
const my %DIRS    => ( '/home/klopp/sdb2/projects' => '/home/klopp/xxx/Google/Backup/projects', );
const my @EDIRS   => qw/
    epic_links  .idea .git .metadata .sync .settings
    .cproject .project .Debug .Release
    /;
const my @EFILES => qw/*.o *.bak/;

my @RKEYS = qw/
    -q
    -pvzD
    -I
    --recursive
    --size-only
    --delete
    /;
push @RKEYS, map { sprintf '--exclude="%s"', $_ } @EDIRS, @EFILES;

my @EXCL;
for (@EDIRS) {
    my $rx = "\/$_\$";
    $rx =~ s/[.]/[.]/gsm;
    push @EXCL, qr{$rx};
    $rx =~ s/\$$/\/.\*/gsm;
    push @EXCL, qr{$rx};
}
for (@EFILES) {
    my $rx = "$_\$";
    $rx =~ s/[.]/[.]/gsm;
    $rx =~ s/[*]/.*/gsm;
    push @EXCL, qr{$rx};
}

# ------------------------------------------------------------------------------
sub END
{
    my ($self) = @_;
    threads->exit;
}

# ------------------------------------------------------------------------------
Log::Any::Adapter->set( 'Fille', file => '/home/klopp/tmp/log/rsync.log' );
my %locks : shared;
my $q = Thread::Queue->new();

# ------------------------------------------------------------------------------
my $task = threads->new(
    sub {
        local $SIG{INT} = sub { threads->exit };

        my $watcher = File::ChangeNotify->instantiate_watcher(
            directories    => [ keys %DIRS ],
            exclude        => \@EXCL,
            sleep_interval => 1,
        );
        while ( my @events = $watcher->wait_for_events ) {
            for my $e (@events) {
                next if $e->type !~ /^create|modify|delete$/sm;
                $q->enqueue(
                    {   name  => $e->path,
                        event => $e->type,
                        type  => ( -d $e->path ? 'dir' : 'file' ),
                    },
                );
            }
        }
    },
);
$task->detach;

# ------------------------------------------------------------------------------
my $tid = 0;
for ( 1 .. $THREADS ) {
    ++$tid;
    $task = threads->new(
        sub {
            local $SIG{INT} = sub { threads->exit };
            while (1) {
                my @events;
                while ( defined( my $e = $q->dequeue ) ) {

                    my $skip = 0;
                    for ( keys %locks ) {
                        next unless exists $locks{$_};
                        if ( $e->{name} eq $_ ) {
                            ++$skip;
                            last;
                        }
                        if ( $e->{type} ne $locks{$_} ) {
                            local $a = $e->{name};
                            local $b = $_;
                            if ( length $a > length $b ) {
                                $a = $_;
                                $b = $e->{name};
                            }
                            if ( index( $a, $b ) == -1 ) {
                                ++$skip;
                                last;
                            }
                        }
                    }

                    if ($skip) {
                        unshift @events, $e;
                        next;
                    }
                    $locks{ $e->{name} } = $e->{type};
                    _i( '[%s] "%s" => %s (%s)', $tid, $e->{name}, $e->{event}, $e->{type} );
                    for ( sort { length $a <=> length $b } keys %DIRS ) {
                        if ( index( $e->{name}, $_ ) != -1 ) {
                            my $remote = $e->{name};
                            $remote =~ s/^$_\///gsm;
                            my ( undef, $rpath ) = fileparse($remote);
                            $rpath = sprintf '%s/%s', $DIRS{$_}, $rpath;
                            _i( 'OK, $rpath: "%s"', $rpath );
                            make_path($rpath);
                            my @sync
                                = ( q{/usr/bin/rsync}, @RKEYS, $e->{name}, sprintf q{%s/%s}, $DIRS{$_}, $remote );
                            my $err;
                            run \@sync, sub { }, sub { }, \$err;
                            $err and _e($err);
                        }
                    }
                    delete $locks{ $e->{name} };
                }
                @events and $q->enqueue(@events);
                sleep 1;
            }
        }
    );
    $task->detach;
}

# ------------------------------------------------------------------------------
while (1) {
    sleep 1;
}

# ------------------------------------------------------------------------------
sub _i
{
    my ( $fmt, @args ) = @_;
    say sprintf $fmt, @args;
    $log->infof( $fmt, @args );
}

# ------------------------------------------------------------------------------
sub _e
{
    my (@args) = @_;
    say sprintf 'ERROR: %s', @args;
    $log->errorf(@args);
}

# ------------------------------------------------------------------------------
