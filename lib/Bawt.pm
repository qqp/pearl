package Bawt;

use strict;
use warnings;

use Bawt::IRC;
use Bawt::SendQ qw (raw);

use Class::Load ':all';
use Config::JSON;

our $irc;
our $modules;
my $config;

sub config {
    my $cj = Config::JSON->new("config.json"); # FIXME: error handling.
    $config = $cj->get();   # Ditto.

    $config->{flood} //= 0;
    $config->{maxburst} //= 6;

    Bawt::SendQ::config({
            "flood" => $config->{flood},
            "maxburst" => $config->{maxburst}
        });

    Bawt::IRC::config($config->{irc});
}

sub modules_config {
    foreach my $module (keys $config->{modules}) {
        use Data::Dumper;

        my ($flag, $error) = try_load_class("Bawt::Plugin::$module");
        if ($flag) {
            $modules{$module} = "Bawt::Plugin::$module"->new($config->{modules}{$module});
            print "Loaded Bawt::Plugin::$module\n";
        } else {
            print "Error loading module Bawt::Plugin::$module: $error\n";
        }
    }
}

sub run {
    my $cv = AE::cv;
    $irc = Bawt::IRC::new();

    modules_config();

    Bawt::IRC::run();
    $cv->recv;
}

sub new {
    my $me = shift;
    my $self = {};
    bless $self, $me;

    config();
    # Figure out what, if any, configuration to take from the user... config file, I guess.

    return $self;
}

1;
