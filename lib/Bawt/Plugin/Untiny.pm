package Bawt::Plugin::Untiny;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::HTTP;
use Regexp::Common qw/URI/;
use URI::Escape;

use Bawt::IRC;
use Bawt::RateLimiter;
use Bawt::Utils;

my $config;

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    $config->{max_urls} //= '15:60';
    my ($count, $seconds) = split /:/, $config->{max_urls};
    my $rate = Bawt::RateLimiter->new(actions => $count, time => $seconds);
            
    $Bawt::irc->reg_cb(
        irc_privmsg => 500, sub {
            my ($self, $msg) = @_;
            my $heap = $self->heap();

            return if (Bawt::Userlist::is_ignored($msg->{prefix}));

            my $text = $msg->{'params'}[1];
            if ($text =~ m<^!untiny\s+($RE{URI}{HTTP})>i) {
                $self->stop_event;
                return if (!$rate->check());
                my $origurl = $1;
                my $url = uri_escape($origurl);
                get_http "http://untiny.me/api/1.0/extract/?url=$url&format=text", 1024, sub {
                    my $body = shift;
                    Bawt::IRC::msg(target $msg, "$origurl -> $body");
                };
            }
        }
    );

    return $self;
}

1;
