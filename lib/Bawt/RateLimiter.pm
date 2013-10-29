package Bawt::RateLimiter;

use strict;
use warnings;

use Carp qw(croak);

sub check {
    my $self = shift;
    if ($#{$self->{history}} > -1) {
        while ($#{$self->{history}} > -1 &&
                AE::now - @{$self->{history}}[0] > $self->{time}) {

            shift $self->{history};
        }
        return 0 if ($#{$self->{history}} + 2 >= $self->{actions} &&
                      AE::now - @{$self->{history}}[0] < $self->{time});
    }
    push @{$self->{history}}, AE::now;
    return 1;
}

sub new {
    my $me = shift;
    croak __PACKAGE__ . '->new() params must be a hash' if @_ % 2;
    my %params = @_;
    my $self = bless \%params, $me;

    $self->{actions} ||= 10;
    $self->{time} ||= 60;
    $self->{history} = ();

    return $self;
}

1;
