package Bawt;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Log;
use Class::Load ':all';
use Config::JSON;
use FindBin;
use File::Spec::Functions qw(file_name_is_absolute splitpath catdir catfile);

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

    $config->{basedir} //= $FindBin::RealBin;
    Bawt::Userlist::config({
        "userlist" => fix_up_path($config->{userlist})
    });

    Bawt::SendQ::config($config->{sendq});
    Bawt::IRC::config($config->{irc});
}

# Make sure relative path references go somewhere sane.
sub fix_up_path {
    my $origpath = shift;

    return $origpath if (file_name_is_absolute($origpath));

    my ($dir, $file) = (splitpath($origpath))[1,2];
    return catfile(catdir($config->{basedir}, @_, $dir), $file);
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

    return $self;
}

1;
