package Bawt::Plugin::URL;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::HTTP;
use HTML::PullParser;
use Regexp::Common qw/URI/;

use Bawt::IRC;
use Bawt::RateLimiter;
use Bawt::Utils;

my $config;

sub __get_title {
    my ($body, $hdr, $params) = @_;
    my $title;

    my ($url, $msg) = @$params;

    if ($hdr->{Type} eq 'text/html' ||
            $hdr->{Type} eq 'application/xhtml' ||
            $hdr->{Type} eq 'application/xhtml+xml') {

        my $p = HTML::PullParser->new( 
            doc => $body,
            start => 'event',
            end => 'event',
            text => 'event, dtext',
            report_tags => [qw(title)]
        );

        my $watching = 0;
        while (my $token = $p->get_token) {
            my $event = shift(@{$token});
            if ($event eq 'start') { $watching = 1; }
            elsif ($event eq 'end') { $watching = 0; }
            elsif ($event eq 'text' && $watching) {
                $title = shift(@{$token});
                $title =~ s/(^\s+|\s+$)//mg;
                $title =~ s/\s+/ /mg;
                last;
            }
        }
    }

    chomp $title;
    my $target = target $msg;
    if (length($url) >= 35) {
        shorten $url, sub {
            my $min = shift;
            if ($min ne $url || $title) {
                Bawt::IRC::msg($target, ($title) ? "$title -> $url" : "$url ($hdr->{Type})", 1);
            }
        };
    } elsif ($title) {
        Bawt::IRC::msg($target, "$title -> $url", 1);
    }
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    $config->{max_urls} //= '15:60';
    my ($count, $seconds) = split /:/, $config->{max_urls};
    my $rate = Bawt::RateLimiter->new(actions => $count, time => $seconds);

    $Bawt::irc->reg_cb(
        irc_privmsg => sub {
            my ($self, $msg) = @_;

            return if (Bawt::Userlist::is_ignored($msg->{prefix}));

            my $what = $msg->{params}[1];
            while ($what =~ m/\b($RE{URI}{HTTP}{-scheme => 'https?'})/gi) {
                last if (!$rate->check());
                my $url = $1;
                get_http $url, 131072, \&__get_title, [ $url, $msg ];
            }
          }
    );

    return $self;
}

1;
