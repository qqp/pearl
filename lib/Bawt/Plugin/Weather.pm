package Bawt::Plugin::Weather;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::HTTP;
use XML::Simple;
use URI::Escape;

use Bawt::IRC;
use Bawt::RateLimiter;
use Bawt::Utils;

my $config;

sub __get_weather {
    my ($body, $hdr, $params) = @_;

    my ($msg) = @$params;

    my $x = XML::Simple->new;
    my $w = eval { $x->parse_string($body) };

    if ($@) {
        Bawt::IRC::msg(target $msg, "Error, I probably got bad XML", 1);
        return;
    }

    my @forecast = @{$w->{forecast}{txt_forecast}{forecastdays}{forecastday}}; 
    my $location = $w->{location};
    my $city = "\002$location->{city}\002";
    my $state = $location->{state};
    my $country = $location->{country};

    $location = (ref($state)) ? "$city, $country" : "$city, $state, $country";

    my $today = "\002$forecast[0]->{title}\002 -> $forecast[0]->{fcttext_metric}";
    my $idx = ($forecast[1]->{title} =~ m/night/i) ? 2 : 1;
    my $tomorrow = "\002$forecast[$idx]->{title}\002 -> $forecast[$idx]->{fcttext_metric}";

    Bawt::IRC::msg(target $msg, "Weather for $location: $today $tomorrow", 2);
}

sub __lookup_location {
    my ($body, $hdr, $params) = @_;

    my ($msg) = @$params;

    my $x = XML::Simple->new;
    my $w = eval { $x->parse_string($body) };

    if ($@) {
        Bawt::IRC::msg(target $msg, "Error, I probably got bad XML", 1);
        return;
    }

    if (!%$w) {
        Bawt::IRC::msg(target $msg, "Couldn't find that city.", 1);
        return;
    }

    my ($name, $code);

    if (ref($w->{l})) {
        $code = $w->{l}[0];
        my $name = $w->{name}[0];
        if ($w->{c}[0] eq "(null)" || index($name,",") == -1) {
            Bawt::IRC::msg(target $msg, "I only know how to get the weather for cities.", 1);
            return;
        }
    } else {
        if ($w->{type} ne "city") {
            Bawt::IRC::msg(target $msg, "I only know how to get the weather for cities.\n", 1);
            return;
        }
        $code = $w->{l};
    }

    my $apikey = $config->{apikey};
    get_http "http://api.wunderground.com/api/$apikey/geolookup/forecast$code.xml", 0, \&__get_weather, [ $msg ];
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;
                
    $config->{max_weather} //= '6:60';
    my ($count, $seconds) = split /:/, $config->{max_weather};
    my $rate = Bawt::RateLimiter->new(actions => $count, time => $seconds);
            
    $Bawt::irc->reg_cb(
        irc_privmsg => sub {
            my ($self, $msg) = @_;

            return if (Bawt::Userlist::is_ignored($msg->{prefix}));

            my $what = $msg->{params}[1];
            if ($what =~ m<^!w\s+(.+)>i) {
                $self->stop_event;
                return if (!$rate->check());

                my $loc = uri_escape($1);
                get_http "http://autocomplete.wunderground.com/aq?query=$loc\&format=xml\&h=0", 0, \&__lookup_location, [ $msg ];
            }
        }
    );

    return $self;
}

1;
