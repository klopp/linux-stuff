#!/usr/bin/perl

# ------------------------------------------------------------------------------
use utf8::all;
use open qw/:std :utf8/;
use Modern::Perl;

# ------------------------------------------------------------------------------
use Const::Fast;
use File::Basename q/fileparse/;
use File::ChangeNotify;
use forks;
use forks::shared;
use IPC::Run qw/run/;
use Log::Any qw/$log/;
use Log::Any::Adapter;
use Thread::Queue;

# ------------------------------------------------------------------------------
const my $THREADS => 1;
const my %DIRS    => ( '/home/klopp/sdb2/projects' => '/home/klopp/xxx/Google/Backup/projects', );
const my @EDIRS   => qw/
    epic_links  .idea .git .metadata .sync .settings
    .cproject .project .Debug .Release
    /;
const my @EFILES => qw/*.o *.bak/;

const my @RKEYS => qw/
    -pvzD
    -I
    --recursive
    --size-only
    --delete
    /;
my $RSYNC = sprintf q{/usr/bin/rsync %s --exclude="%s" %%s %%s/%%s}, join( q{ }, @RKEYS ),
    join( '" --exclude="', @EDIRS, @EFILES );

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
my $tid = 1;
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
                    }
                    else {
                        $locks{ $e->{name} } = $e->{type};
                        say sprintf '[%s] "%s" => %s (%s)', $tid, $e->{name}, $e->{event}, $e->{type};
                        $log->infof( '[%s] "%s" => %s (%s)', $tid, $e->{name}, $e->{event}, $e->{type} );
                        for ( sort { length $a <=> length $b } keys %DIRS ) {
                            if ( index( $e->{name}, $_ ) != -1 ) {
                                my $remote = $e->{name};
                                $remote =~ s/^$_\///gsm;
                                my $sync = sprintf $RSYNC, $e->{name}, $DIRS{$_}, $remote;
                                say $sync;
                                $log->infof($sync);
                                my $out_and_err;
                                $sync = 'true';
                                run [$sync], '>&', \$out_and_err;
                                say sprintf '%s', $out_and_err;
                                $log->infof( '%s', $out_and_err );
                            }
                        }
                        delete $locks{ $e->{name} };
                    }
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
