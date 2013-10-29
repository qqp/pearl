package Bawt::SendQ;

use strict;
use warnings;

use Bawt::IRC;
use AnyEvent;

my $flood = 0;
my $penalty = 0;
my $maxburst = 0;

my @high_priority_queue;
my @low_priority_queue;

my $queue_pop_timer;
my $penalty_lower_timer;

sub config {
    my $c = shift;
    $maxburst = $c->{maxburst};
    $flood = $c->{flood};
}

sub __penalty_lower {
    if ($#high_priority_queue < 0 && $#low_priority_queue < 0 && !$penalty) {
        $penalty_lower_timer = undef;
        return;
    }
    if ($penalty) { $penalty--; }
}

sub __queue_pop {
    if (!Bawt::IRC::is_connected()) {
        empty_queue();
        return;
    }

    return if ($penalty >= $maxburst);

    for (; $flood || $penalty < $maxburst; $penalty++) {
        if ($#high_priority_queue > -1) {
            $Bawt::irc->send_msg(@{ shift @high_priority_queue });
        } elsif ($#low_priority_queue > -1) {
            $Bawt::irc->send_msg(@{ shift @low_priority_queue });
        } else {
            $queue_pop_timer = undef;
            last;
        }
    }

    if ($flood) {
        $penalty_lower_timer //= AE::timer 1, 1, \&__penalty_lower;
    } else {
        $penalty = 0;
    }
}

sub send_high_priority {
    return unless Bawt::IRC::is_connected();    # FIXME: should be == 2, add a separate routing to let the bot connect...
    push @high_priority_queue, [@_];
    if (!$flood) { $queue_pop_timer //= AE::timer 1, 1, \&__queue_pop; }
    &__queue_pop();
}

sub send_low_priority {
    return unless Bawt::IRC::is_connected() == 2;

}

sub empty_queue {
    $penalty = 0;
    $high_priority_queue = ();
    $low_priority_queue = ();
    $qpop_timer = undef;
    $penalty_lower_timer = undef;
}

sub new {
    my $me = shift;
    my $self = {};
    bless $self, $me;
    return $self;
}

1;
