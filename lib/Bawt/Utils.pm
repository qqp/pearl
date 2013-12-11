package Bawt::Utils;

use strict;
use warnings;

use Bawt::IRC;

use AnyEvent::HTTP;
use HTML::PullParser;
use URI::Escape;
use Encode;
use Encode::Guess;
 
use base Exporter::;
our @EXPORT = qw(get_http shorten target); 

# Wrapper for http_request to limit response sizes. Suggests/requires the
# ae-http.diff patch.
sub get_http($$$;$) {
    my ($url, $max, $cb, $params) = @_;
    my $x = sub {
        my $data = '';
        my $size = 0;
        http_request
            GET => $url,
            recurse => 3,
            headers => { "user-agent" => "bawt 0.1" },
            timeout => 5,
            max_chunk_size => $max,
            on_body => sub {
                my ($body, $hdr) = @_;
                $size += length($body);
                $data .= $body;

                if ($max) { return ($size <= $max); }
                1;
            },
            on_header => sub {
                $data = '';
                1;
            },
            sub {
                my ($body, $hdr) = @_;

                if ($hdr->{Status} !~ /^2/
                    && ($hdr->{Status} != 598 || $hdr->{OrigStatus} !~ /^2/)) {

                    $data = "Error";
                    $cb->($data, $hdr, $params);
                    return;
                }

                $data = substr($data, 0, $max) if $max;

                my ($type,$encoding);
                my @contenttype = undef;
                if (defined($hdr->{'content-type'})) {
                    @contenttype = map {
                        s/\s+$//;
                        s/^\s+//;
                        $_;
                    } split /;/, $hdr->{'content-type'};

                    $type = $contenttype[0];
                    for (my $i = 1; $i < $#contenttype + 1; $i++) {
                        my ($key, $val) = split /=/, $contenttype[$i];
                        if ($key eq "charset") { $encoding = $val; last; }
                    }
                } else {
                    $type = "Unknown";
                }

                if ($type eq "text/html" ||
                        $type eq "application/xhtml" ||
                        $type eq "application/xhtml+xml") {

                    # Allow content-type tags to override the server-provided content-type.
                    my $p = HTML::PullParser->new(doc => $data, start => 'attr', report_tags => [qw(meta)]);
                    while (my $token = $p->get_token) {
                        my $attr = shift( @{$token} );
                        if (defined($attr->{'http-equiv'}) && $attr->{'http-equiv'} =~ /content-type/i) {
                            @contenttype = map {
                                s/\s+$//;
                                s/^\s+//;
                                $_;
                            } split /;/, $attr->{content};
                            last if (!@contenttype);
                            for (my $i = 1; $i < $#contenttype + 1; $i++) {
                                my ($key, $val) = split /=/, $contenttype[$i];
                                if ($key eq "charset") { $encoding = $val; last; }
                            }
                            last;
                        }
                    }
                }

                if ($encoding && $encoding !~ /^utf/i) { Encode::Guess->set_suspects($encoding); }

                my $tmp = eval { decode("Guess", $data); };
                if (!$@) { $data = $tmp; }

                $hdr->{Encoding} = $encoding;
                $hdr->{Type} = $type;
            
                $cb->($data, $hdr, $params);
            };
    };
    &$x();
}

# Shorten a URL.
sub shorten($$) {
    my ($url, $cb) = @_;
    my $temp_url = uri_escape_utf8($url);
    get_http "http://is.gd/create.php?format=simple&url=$temp_url", 1024, sub { 
        my ($body, $hdr) = @_;
        $cb->(($hdr->{Status} =~ /^2/ ) ? $body : $url);
    };
}

sub target($) {
    my $msg = shift;
    return ($msg->{params}[0] eq Bawt::IRC::nick())
        ? (split /!/, $msg->{prefix}, 2)[0]
        : $msg->{params}[0];
}

1;
