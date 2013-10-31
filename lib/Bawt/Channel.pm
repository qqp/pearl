package Bawt::Channel;

use strict;
use warnings;

use AnyEvent;

my $config;
my $recheck_timer;
my $recheck_interval = 10;

my @channel_list = ();

# Join channels, and try to stay on the channels we're told.

sub __check_removed_user {
    my ($self, $msg) = @_;
    
    if (defined($msg->{params}[1]) && $msg->{params}[1] eq Bawt::IRC::nick()) {
        my ($i) = grep { $msg->{params}[0] eq $channel_list[$_] } 0 .. $#channel_list;
        splice @channel_list, $i, 1;
    }
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    $Bawt::irc->reg_cb(
        irc_001 => sub {
            my ($self, $msg) = @_;
            Bawt::IRC::raw("JOIN", $_) for (keys $config);

            # FIXME: can probably rework this to only run when we're not on at
            # least one channel.
            $recheck_timer = AE::timer $recheck_interval, $recheck_interval, sub {
                return unless Bawt::IRC::is_connected();
        
                my %diff;

                {
                    # Perl helpfully (and incorrectly) suggests $diff instead of @diff,
                    # so turn off the warning.
                    no warnings;
                    @diff{ keys $config } = undef;
                }

                delete @diff{ @channel_list };
                Bawt::IRC::raw("JOIN", $_) for (keys %diff);
            };
        },
        irc_join => sub {
            my ($self, $msg) = @_;
            if ((split /!/, $msg->{prefix}, 2)[0] eq Bawt::IRC::nick()) {
                push @channel_list, $msg->{params}[0];
            }
        },
        irc_part => \&__check_removed_user,
        irc_kick => \&__check_removed_user,
        connect  => sub {
            @channel_list = ();
        },
        disconnect => sub {
            @channel_list = ();
            $recheck_timer = undef;
        }
    );

    return $self;
}

1;
