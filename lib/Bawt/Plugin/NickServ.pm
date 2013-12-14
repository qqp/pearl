package Bawt::Plugin::NickServ;

use strict;
use warnings;

use AnyEvent;
use Bawt::IRC;

my $config;
my $identified = 0;
my $id_timer;

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;

    $config = $cfg;

    $Bawt::irc->reg_cb(
        connect => 1000, sub {
            if (defined($config->{nickserv_user}) &&
                    defined($config->{nickserv_pass})) {

                $identified = 0;
                Bawt::IRC::raw("PASS",
                    "$config->{nickserv_user}:$config->{nickserv_pass}");
                $id_timer = AE::timer 30, 0, sub {
                    if (!$identified) {
                        Bawt::IRC::raw("PRIVMSG", "NickServ",
                            "IDENTIFY $config->{nickserv_user} $config->{nickserv_pass}");
                    }
                }
            }
        },
        disconnect => 1000, sub {
            $identified = 0;
        },
        irc_notice => 1000, sub {
            my ($self, $msg) = @_;
            if ($msg->{prefix} eq "NickServ!NickServ\@services.") {
                my $wanted = Bawt::IRC::desired_nick();
                if ($msg->{params}[1] =~ /^You are now identified for/) {
                    AE::log info => "Identified for $config->{nickserv_user}.";
                    $identified = 1;
                    $id_timer = undef;
                    if (Bawt::IRC::nick() ne $wanted) {
                        Bawt::IRC::raw("NICK", $wanted);
                    }
                } elsif ($msg->{params}[1] =~ /has been ghosted.$/) {
                    AE::log info => "Ghosted nick $wanted.";
                    Bawt::IRC::raw("PRIVMSG", "NickServ", "RELEASE $wanted");
                } elsif ($msg->{params}[1] =~ /has been released.$/) {
                    AE::log info => "Released nick $wanted.";
                    Bawt::IRC::raw("NICK", $wanted);
                }
            }
        },
        irc_433 => 1000, sub {
            my ($self, $msg) = @_;
            my $wanted = Bawt::IRC::desired_nick();
            if ($msg->{params}[1] eq $wanted && $identified) {
                Bawt::IRC::raw("PRIVMSG", "NickServ", "GHOST $wanted");
                $self->stop_event();
            }
        },
        irc_437 => 1000, sub {
            my ($self, $msg) = @_;
            my $wanted = Bawt::IRC::desired_nick();
            if ($msg->{params}[1] eq $wanted && $identified) {
                Bawt::IRC::raw("PRIVMSG", "NickServ", "RELEASE $wanted");
                $self->stop_event();
            }
        }
    );

    return $self;
}

1;
