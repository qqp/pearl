package Bawt;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Log;
use Class::Load ':all';
use Config::JSON;

use Bawt::IRC;
use Bawt::Channel;
use Bawt::SendQ;
use Bawt::Userlist;

our $irc;
our %modules;
my $config;

my $channels;

sub __config {
    my $config_file = shift;

    AE::log note => "Configuring using $config_file\n";

    my $cj = eval { Config::JSON->new($config_file); };
    if ($@) { AE::log error => "Error parsing config file \"config.json\""; $@ = undef; die; }

    $config = $cj->get();

    $config->{sendq}{flood} //= 0;
    $config->{sendq}{maxburst} //= 6;

    Bawt::Userlist::config({
        "userlist" => $config->{userlist}
    });

    Bawt::SendQ::config($config->{sendq});
    Bawt::IRC::config($config->{irc});
}

sub modules_config {
    $channels = Bawt::Channel->new($config->{channels} // {});

    foreach my $module (keys $config->{modules}) {
        my ($flag, $error) = try_load_class("Bawt::Plugin::$module");
        if ($flag) {
            $modules{$module} = "Bawt::Plugin::$module"->new($config->{modules}{$module});
            AE::log note => "Loaded Bawt::Plugin::$module";
        } else {
            AE::log error => "Error loading module Bawt::Plugin::$module: $error";
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

    $AnyEvent::Log::FILTER->level("info");

    my $config_file = shift;
    __config($config_file);
    # Figure out what, if any, configuration to take from the user... config file, I guess.

    return $self;
}

1;
