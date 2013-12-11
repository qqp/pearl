package Bawt::Cache;

use strict;
use warnings;

use Carp qw(croak);
use Storable;

# This is only half a cache, currently it will only store a value and verify
# that a value exists. It is used to help prevent duplicate urls from being
# shortened or displayed.
#
# FIXME: This should be extended to cache shortened/feed-stripped URLs too.

sub cache_thing {
    my ($self, $thing) = @_;
    if (!defined($self->{cache_h}{$thing})) {
        $self->{cache_h}{$thing} = 1;
        unshift(@{$self->{cache_l}}, $thing);
        if ($#{$self->{cache_l}} >= $self->{maxsize}) {
            my $tmp = pop(@{$self->{cache_l}});
            delete $self->{cache_h}{$tmp};
        }
    }
}

sub is_cached {
    my ($self, $thing) = @_;
    return defined($self->{cache_h}{$thing});
}

sub save {
    my $self = shift;
    store \@{$self->{cache_l}}, "cache/$self->{filename}.cache";
}

sub new {
    my $me = shift;
    croak __PACKAGE__ . '->new() params must be a hash' if @_ % 2;
    my %params = @_;
    my $self = bless \%params, $me;

    $self->{filename} ||= 'cache';
    $self->{maxsize}  ||= 500;

    $self->{cache_l} = ();
    $self->{cache_h} = ();

    if ( -e "cache/$self->{filename}.cache") {
        $self->{cache_l} = retrieve("cache/$self->{filename}.cache");

        if ($#{$self->{cache_l}} > $self->{maxsize}) {
            $#{$self->{cache_l}} = $self->{maxsize} - 1;
        }
        foreach my $thing (@{$self->{cache_l}}) {
            $self->{cache_h}{$thing} = 1;
        }
    }

    return $self;
}

1;
