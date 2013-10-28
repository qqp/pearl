package Bawt::IRC;

use Bawt::SendQ;

use AnyEvent;
use AnyEvent::IRC::Connection;
use AnyEvent::IRC::Util qw(mk_msg);
use EV;
use List::Util qw(shuffle);

use Data::Dumper;

my $connected = 0;
my $reconnect_timer;
my $stoned_timer;
my $stoned_last_time;
my $server_index = -1;
my $config;

my $bot_nick;
my $bot_nuh;

our $max_nick_len;       # Probably safe defaults.
our $max_channel_len;
our $max_topic_len;

sub config {
    $config = shift;

    $config->{nick} //= "bot";
    $config->{alt_nick} //= "$config->{nick}_";
    $config->{user_name} //= "bot";
    $config->{real_name} //= "bot";
    $config->{use_ssl} //= 0;

    $config->{connect_timeout} //= 15;
    $config->{stoned_timeout} //= 240;
    $config->{reconnect_time} //= 15;

    $max_nick_len = $config->{max_nick_len} // 9;
    $max_nick_len = $config->{max_channel_len} // 30;
    $max_nick_len = $config->{max_topic_len} // 320;

    # FIXME: add a check for an empty server list... better error 
}

sub __next_server {
    $server_index = ($server_index + 1) % @{$config->{server_list}};
    my ($host, $port) = split /:/, $config->{server_list}[$server_index];
    $port //= 6667;
    return [ $host, $port ];           
}

sub __mangle_nick {
    my $nick = shift;
    return (length($nick) >= $max_nick_len) ? join('', shuffle(split('', $nick))) : "${nick}_";
}

my $nick_change_error = sub {
    my ($self, $msg) = @_;
    raw("NICK", ($msg->{params}[1] eq $config->{nick})
            ? $config->{alt_nick}
            : __mangle_nick($msg->{params}[1])
    );
};

my $conn_cb = sub {
    my $fh = shift;

    if (defined($config->{bind_address})) {
        my $bind = AnyEvent::Socket::pack_sockaddr 0,
            AnyEvent::Socket::parse_address($config->{bind_address});
        bind $fh, $bind;
    }

    return $config->{connect_timeout};
};

sub __init {
    my $irc = AnyEvent::IRC::Connection->new();

    if ($config->{use_ssl} == 1) {
        $irc->enable_ssl();
    }

    $irc->reg_cb(
        connect => 1001, sub {
            # The SendQ module won't add items to the queue unless the bot is
            # connected. This needs to be a high priority block so plugins can
            # send things before the main on-connect sub is called.
            $connected = 1;
        },
        connect => 500, sub {
            my ($self, $error) = @_;

            if ($error) {
                $reconnect_timer = AE::timer $config->{reconnect_time}, 0, sub {
                    $self->connect(@{ __next_server() }, $conn_cb);
                };
            } else {
                $stoned_timer = AE::timer $config->{stoned_time}, $config->{stoned_time}, sub {
                    if ($stoned_last_time && time - $stoned_last_time > $config->{stoned_timeout}) {
                        $self->disconnect("Server is stoned");
                    } else {
                        raw("PING", time);
                    }
                };
            }

            raw("NICK", $config->{nick});
            raw("USER", $config->{user_name}, "*", "0", $config->{real_name});
        },
        disconnect => 500, sub {
            my $self = shift;

            $connected = 0;
            Bawt::SendQ::empty_queue();
            $stoned_timer = undef;
            $stoned_last_time = 0;
            $reconnect_timer = AE::timer $config->{reconnect_time}, 0, sub {
                $self->connect(@{ __next_server() }, $conn_cb);
            };
        },
        irc_nick => 500, sub {
            my ($self, $msg) = @_;
            my $who = (split(/!/, $msg->{prefix}))[0];
            if ($who eq $bot_nick) {
                $bot_nick = $msg->{params}[0];
                $bot_nuh = $bot_nick . "!" . (split(/!/, $bot_nuh))[1];
            }
        },
        irc_ping => 500, sub {
            my ($self, $msg) = @_;
            raw("PONG", $msg->{params}[0]);
        },
        irc_pong => 500, sub {
            my ($self, $msg) = @_;
            $stoned_last_time = time;
            if ($stoned_last_time - $msg->{params}[1] >= $config->{stoned_timeout}) {
                $self->disconnect("Server is stoned");
            }
        },
        irc_001 => 500, sub {
            my ($self, $msg) = @_;
            if (defined($config->{oper})) {
                raw("OPER", $config->{oper});
            }
            $connected = 2;
            $bot_nick = $msg->{params}[0];
            raw("WHOIS", $bot_nick);
        },
        irc_005 => 500, sub {                                # Parse ISUPPORT
            my ($self, $msg) = @_;
            foreach my $token (@{$msg->{params}}) {
                if ($token =~ m/NICKLEN=(\d+)/) {
                    $max_nick_len = $1;
                } elsif ($token =~ m/CHANNELLEN=(\d+)/) {
                    $max_channel_len = $1;
                } elsif ($token =~ m/TOPICLEN=(\d+)/) {
                    $max_topic_len = $1;
                }
            }
        },
        irc_311 => 500, sub {
            my ($self, $msg) = @_;
            my ($nick, $user, $host) = @{$msg->{params}}[1..3];
            $bot_nuh = "$nick!$user\@$host";
        },
        irc_433 => 500, $nick_change_error,
        irc_436 => 500, $nick_change_error,
        irc_437 => 500, $nick_change_error,
        read => sub {
            my ($self, $msg) = @_;
            print "Received: ".Dumper($msg)."\n";
        },
        send => sub {
            my ($self, $msg) = @_;
            print "Sent: ".Dumper($msg)."\n";
        }
    );

    return $irc;
}

sub run {
    $Bawt::irc->connect(@{ __next_server() }, $conn_cb);
}

sub desired_nick {
    return $config->{nick};
}

sub nick {
    return $bot_nick;
}

sub nuh {
    return $bot_nuh;
}

sub raw {
    Bawt::SendQ::send_high_priority(@_);
}

sub msg {
    Bawt::SendQ::send_low_priority(@_);
}

sub is_connected {
    return $connected;
}

sub new {
    return __init();
}

1;
