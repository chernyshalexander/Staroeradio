#!/usr/bin/env perl
# Test cover art parsing from staroeradio.ru track pages.
# Replicates _parseCoverFromPage() from Plugin.pm to verify the logic
# against real pages before/while testing inside LMS.

use strict;
use warnings;
use utf8;
use HTML::TokeParser;
use LWP::UserAgent;
use Encode qw(decode);

binmode(STDOUT, ':utf8');

my $ua = LWP::UserAgent->new(timeout => 20);
$ua->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36');

# Same parsing logic as Plugin.pm _parseCoverFromPage
sub parse_cover_from_page {
    my ($html, $site) = @_;

    return undef unless defined $html;

    my $p = HTML::TokeParser->new(\$html) or return undef;

    while (my $token = $p->get_tag('div')) {
        my $class = $token->[1]{class} || '';
        next unless $class eq 'images';

        while (my $inner = $p->get_token) {
            last if $inner->[0] eq 'E' && $inner->[1] eq 'div';

            if ($inner->[0] eq 'S' && $inner->[1] eq 'a') {
                my $href = $inner->[2]{href};
                if ($href && $href =~ /\.(?:jpe?g|png|gif)$/i) {
                    return absolute_image_url($href, $site);
                }
            }

            if ($inner->[0] eq 'S' && $inner->[1] eq 'img') {
                my $src = $inner->[2]{src};
                if ($src && $src =~ /\.(?:jpe?g|png|gif)$/i) {
                    $src =~ s/s(\.(?:jpe?g|png|gif))$/$1/i;
                    return absolute_image_url($src, $site);
                }
            }
        }
    }

    return undef;
}

sub absolute_image_url {
    my ($url, $site) = @_;

    return $url if $url =~ m{^https?://}i;
    return "https://" . ($site || 'staroeradio.ru') . $url;
}

# Track page: title + parsed cover
sub fetch_track_cover {
    my ($site, $track_id) = @_;

    my $page_url = "https://$site/audio/$track_id";
    my $response = $ua->get($page_url);

    unless ($response->is_success) {
        return ($track_id, undef, undef, "HTTP " . $response->code);
    }

    my $html = $response->content;
    my $cover = parse_cover_from_page($html, $site);

    my ($title) = $html =~ m{<title>([^<]+)</title>};
    $title = decode('UTF-8', $title) if defined $title;
    $title =~ s/\s+/ /g if $title;

    return ($track_id, $cover, $title, undef);
}

my $site = $ARGV[0] || 'staroeradio.ru';
my @track_ids = @ARGV[1 .. $#ARGV];
@track_ids = (8537, 1200, 5, 30000) unless @track_ids;

print "=" x 70 . "\n";
print "Cover art parsing test: site=$site\n";
print "=" x 70 . "\n\n";

my $found = 0;
my $total = 0;

foreach my $track_id (@track_ids) {
    $total++;
    my ($id, $cover, $title, $error) = fetch_track_cover($site, $track_id);

    print "Track $id: " . ($title // '?') . "\n";

    if ($error) {
        print "  ERROR: $error\n";
    }
    elsif ($cover) {
        $found++;
        print "  Cover: $cover\n";

        # Verify the cover image is downloadable
        my $img = $ua->head($cover);
        if ($img->is_success) {
            my $len = $img->header('Content-Length') || '?';
            my $ct  = $img->header('Content-Type') || '?';
            print "  Image OK: $ct, $len bytes\n";
        }
        else {
            print "  Image FAILED: " . $img->status_line . "\n";
        }
    }
    else {
        print "  No cover found on page\n";
    }
    print "\n";
}

print "=" x 70 . "\n";
print "Result: $found/$total tracks have covers\n";
print "=" x 70 . "\n";
