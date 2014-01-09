package Bawt::Userlist;

use strict;
use warnings;

use AnyEvent;
use Config::JSON;

my @ignore_list = ();

# Eventually I'd like to have users with various privilege bits.
# ... for now it's just a list of ignores.

sub is_ignored {
    my $nuh = shift;
    grep { $nuh =~ m/$_/ } @ignore_list;
}

sub config {
    my $params = shift;

    $params->{userlist} //= "";

    if (!$params->{userlist} || ! -e $params->{userlist}) {
        AE::log error => "No userlist provided \"$params->{userlist}\"";
        die;
        return;
    }
    
    if (! -r $params->{userlist}) {
        AE::log error => "Unable to read userlist \"$params->{userlist}\"";
        die;
        return;
    }

    # FIXME: Should probably be using croak/confess instead of die
    my $cj = eval { Config::JSON->new($params->{userlist}); };
    if ($@) { AE::log error => "Error parsing userlist \"$params->{userlist}\""; $@ = undef; die; }
    my $config = $cj->get();

    if (defined($config->{ignore})) {
        if (ref($config->{ignore}) ne "HASH") {
            AE::log error => "Ignore list should be a hash";
            die;
        }
        @ignore_list = map qr/$_/i, keys $config->{ignore};
    }
}

sub new {
    my ($me, $cfg) = @_;
    my $self = {};
    bless $self, $me;
}

1;
