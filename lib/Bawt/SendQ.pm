package Bawt::SendQ;

use strict;
use warnings;

use Bawt::IRC;
use AnyEvent;
use Encode;

my $flood = 0;
my $penalty = 0;
my $maxburst = 0;

my @high_priority_queue;
my @low_priority_queue;

my $queue_pop_timer;
my $penalty_lower_timer;

sub config {
    my $c = shift;
    $maxburst = $c->{maxburst} // 6;
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
        $penalty = 0;
    } else {
        $penalty_lower_timer //= AE::timer 1, 1, \&__penalty_lower;
    }
}

sub __chunk_by {
    my ($text, $length) = @_;
    my @out = ();

    while (length($text) > $length) {
        push @out, substr($text, 0, $length);
        $text = substr($text, $length);
    }

    push @out, $text if ($text);

    return @out;
}

# Data in the high priority queue gets the benefit of the doubt that it will
# fit in a single message.
sub send_high_priority {
    return unless Bawt::IRC::is_connected();    # FIXME: should be == 2, add a separate routing to let the bot connect...

    push @high_priority_queue, [@_];
    if (!$flood) { $queue_pop_timer //= AE::timer 1, 1, \&__queue_pop; }
    &__queue_pop();
}

# Data in the low priority queue doesn't. It's also assumed to be a PRIVMSG.
sub send_low_priority {
    my ($target, $message, $maxlines) = @_;
    return unless Bawt::IRC::is_connected() == 2;

    $message = encode('utf8', $message);
    $message =~ s/\001ACTION /\0777ACTION /g;   # FIXME: do I even want to allow /me?
    $message =~ s/[\000-\001]/ /g;
    $message =~ s/\0777ACTION /\001ACTION /g;

    my @lines = split(/\n/, $message);
    my $limit = $maxlines // 50;

    # IRC messages are always lines of characters terminated with a CR-LF
    # (Carriage Return - Line Feed) pair, and these messages SHALL NOT
    # exceed 512 characters in length, counting all characters including
    # the trailing CR-LF. Thus, there are 510 characters maximum allowed
    # for the command and its parameters.
    # 512 chars per line, including command/target.
    #
    # There 12 non-message characters in a privmsg, so 498 bytes per line.

    my $length = 498 - length($target) - length(Bawt::IRC::nick_user_host());

    # Split the output if it is too long
    @lines = map { __chunk_by($_, $length) } @lines;
    if (@lines > $limit) {
        my $n = @lines;
        @lines = @lines[0 .. ($limit - 1)];
        push @lines, "error: output truncated to $limit of $n lines total"
    }

    push(@low_priority_queue, [ "PRIVMSG", $target, $_ ]) for @lines;
    if (!$flood) { $queue_pop_timer //= AE::timer 1, 1, \&__queue_pop; }
    &__queue_pop(); 
}

sub empty_queue {
    $penalty = 0;
    @high_priority_queue = ();
    @low_priority_queue = ();
    $queue_pop_timer = undef;
    $penalty_lower_timer = undef;
}

sub new {
    my $me = shift;
    my $self = {};
    bless $self, $me;
    return $self;
}

1;
