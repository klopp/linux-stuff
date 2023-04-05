#!/usr/bin/perl

use Modern::Perl;

use Const::Fast;
use Log::Any qw/$log/;
use Log::Any::Adapter;
use File::Basename q/fileparse/;
use File::ChangeNotify;
use forks;
use forks::shared;
use Thread::Queue;

my %locks : shared;
const my $THREADS => 1;
const my %DIRS    => ( '/home/klopp/sdb2/projects' => '/home/klopp/xxx/Google/Backup/projects', );
const my @EDIRS   => qw/
    epic_links  .idea .git .metadata .sync} .settings
    .cproject .project .Debug .Release
    /;
const my @EFILES => qw/.o .bak/;

my @EXCL;
my $RSYNC = sprintf q{
rsync -pvzD
    -I
    --recursive
    --size-only
    --delete
    --exclude="%s"
    %%s
    %%s
}, join( '" --exclude="', @EDIRS, @EFILES );

say $RSYNC;
exit;

for (@EDIRS) {

    #    my $rx = "$_\$";
    #    push @EXCL, qr{$rx};
    #    $rx = "$_/.*";
    #    push @EXCL, qr{$rx};
}

sub END
{
    my ($self) = @_;
    threads->exit;
}

Log::Any::Adapter->set( 'Fille', file => '/home/klopp/tmp/log/rsync.log' );

my $q = Thread::Queue->new();

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

my $tid = 1;
for ( 1 .. $THREADS ) {
    ++$tid;
    my $task = threads->new(
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
                            $a = $e->{name};
                            $b = $_;
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
                                say sprintf $RSYNC, $e->{name}, $DIRS{$_};
                                $log->infof( $RSYNC, $e->{name}, $DIRS{$_} );

                                #                                system sprintf $RSYNC, $e->{name}, $DIRS{$_};
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

while (1) {
    sleep 1;
}
