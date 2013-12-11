package Bawt::Plugin::RSS;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Feed;
use HTML::Entities;

use Bawt::IRC;
use Bawt::Utils;
use Bawt::Cache; 

$XML::Atom::ForceUnicode = 1;

my $cache;
my $config;
my @feeds;
my @strip;

# Try to follow pheedcontent/feedproxy/feedburner URLs to get the actual
# content's URL.
sub __strip_proxy($$) {
    my ($url, $cb) = @_;
    http_request
        HEAD => $url,
        headers => { "user-agent" => "pearl 0.1" },
        recurse => 2,
        timeout => 5,
        sub {
            my ($body, $hdr) = @_;
            my $ret;
            $ret = (!exists($hdr->{URL}) || grep { $hdr->{URL} =~ m/$_/ } @strip)
                ? "Error"
                : $hdr->{URL};
            $cb->($ret);
        };
}

sub __scrape_feed {
    my ($feed_reader, $new_entries, $feed, $error, $feedconfig) = @_;

    for my $entry (@$new_entries) {
        my $link  = $entry->[1]->link;
        my $title = $entry->[1]->title;
        next if ($cache->is_cached($link));
        $cache->cache_thing($link);

        unless ($title) { $title = "No Title"; }
        next if $title eq "Featured Advertiser";    # fuck you wapo
        $title = decode_entities($title);
        if (grep { $link =~ m/$_/ } @strip) {
            __strip_proxy $link, sub {
                my $url = shift;
                if ($url eq "Error") {
                    Bawt::IRC::msg($feedconfig->{target}, "[$feedconfig->{name}] $title -> $link [feed proxy not stripped]\n" );
                } else {
                    shorten $url, sub {
                        Bawt::IRC::msg($feedconfig->{target}, "[$feedconfig->{name}] $title -> $_[0]");
                    }
                }
            };
        } else {
            if ($feedconfig->{twitter}) {
                $title = (split /:/, $title, 2)[1];
                $title =~ s/^ //;
            }
            
            if ($feedconfig->{noshorten}) {
                Bawt::IRC::msg($feedconfig->{target}, "[$feedconfig->{name}] $title -> $link");
            } else {
                shorten $link, sub {
                    Bawt::IRC::msg($feedconfig->{target}, "[$feedconfig->{name}] $title -> $_[0]");
                }
            }
        }
    }
    $cache->save(); 
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    @strip = map qr/$_/i, $config->{strip};

    $cache = Bawt::Cache->new(filename => 'rss', maxsize => 1500);

    foreach my $name (keys($config->{feeds})) {
        my $feedconfig = $config->{feeds}{$name};
        $feedconfig->{stripproxy} //= 0;      # FIXME: this should do something. unpheed should work on other proxies too.
        $feedconfig->{noshorten} //= 0;
        $feedconfig->{twitter} //= 0;
        $feedconfig->{poll} //= 300;
        $feedconfig->{name} = $name;

        if (!($feedconfig->{url} || $feedconfig->{target})) {
            print "Missing target channel or URL for this $feedconfig->{name}!\n";
            next;
        }
        print "Adding $feedconfig->{url} ($feedconfig->{name}, every $feedconfig->{poll}s, messages to $feedconfig->{target})\n";
        push @feeds, AnyEvent::Feed->new(
            url => $feedconfig->{url},
            interval => $feedconfig->{poll},
            on_fetch => sub { &__scrape_feed(@_, $feedconfig); }
        );
    }

    return $self;
}

1;
