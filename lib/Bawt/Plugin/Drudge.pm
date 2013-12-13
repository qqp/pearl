package Bawt::Plugin::Drudge;

use strict;
use warnings;

use AnyEvent;
use HTML::PullParser;

use Bawt::IRC;
use Bawt::Utils;
use Bawt::Cache;

my $config;
my $cache;
my $timer;

my $first_run = 1;

sub __parse_drudge {
    my ($body, $hdr, $params) = @_;
    return if ($body eq "Error");

    my $p = HTML::PullParser->new(
        doc => $body,
        start => 'event, attr',
        comment => 'event, text',
        end => 'event',
        text => 'event, dtext',
        report_tags => [qw(a)]
    );

    my ($ignoring, $watching, $url, $text) = (0, 0, undef, undef);
    while (my $token = $p->get_token) {
        my $event = shift(@{$token});
        if ($event eq 'start') {            # Opening tag, anchor or link?
            my $attr = shift(@{$token});
            next unless (!$ignoring && exists $attr->{href});
            $url = $attr->{href};
            $watching = 1;
        } elsif ($event eq 'text') {        # Link text
            next unless $watching;
            $text = shift(@{$token});
            $text =~ s/(^\s+|\s+$)//g;
            $text =~ s/\s+/ /;
        } elsif ($event eq 'end') {         # Shrink the link
            next if $ignoring;
            if ($text && $url !~ m/^javascript:/) {
                my $derp = $text;           # whee scope.
                if (!$cache->is_cached($url)) {
                    $cache->cache_thing($url);
                    if (!$first_run) {
                        shorten $url, sub { Bawt::IRC::msg($config->{target}, "[drudge] $derp -> $_[0]"); }
                    }
                }
            }
            $url = undef;
            $text = undef;
            $watching = 0;
        } elsif ($event eq 'comment') {
            my $ctext = shift(@{$token});
            $ctext =~ s/\s+//g;
            $ignoring = ($ctext =~ m/^<!--S/ || $ctext =~ m/^<!L/);
            last if ($ctext =~ m/^<!LINKSANDSEARCHES3/);
        }
    }

    $first_run = 0;
    $cache->save();
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    $config->{poll} = $config->{poll} || 300;
    $cache = Bawt::Cache->new(filename => 'drudge', maxsize => 150);

    $timer = AE::timer 0, $config->{poll}, sub {
        get_http "http://drudgereport.com/", 0, \&__parse_drudge;
    };

    return $self;
}

1;
