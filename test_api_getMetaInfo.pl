#!/usr/bin/env perl
# Test script for API getMetaInfo(track_id) - simulates Android app behavior

use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use MIME::Base64;

my $api_base = "http://server.audiopedia.su:8888";
my $ua = LWP::UserAgent->new(timeout => 30);
$ua->default_header('Accept' => 'application/json');

print "=" x 60 . "\n";
print "Testing getMetaInfo API (as Android app does)\n";
print "=" x 60 . "\n\n";

# Test different track_ids
my @test_track_ids = (
    111,      # Detskoe radio
    222,      # Staroe radio
    333,      # Music radio
    1111,     # Sample track 1
    2222,     # Sample track 2
    3333,     # Sample track 3
);

foreach my $track_id (@test_track_ids) {
    my $url = "$api_base/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
    print "Testing track_id: $track_id\n";
    print "URL: $url\n";

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $content = $response->decoded_content;

        # Try to parse as JSON
        eval {
            my $json = decode_json($content);
            print "✓ SUCCESS: JSON received\n";

            if (ref($json) eq 'HASH' && exists $json->{Metainfo}) {
                my $metainfo = $json->{Metainfo};
                print "  Metainfo.text: " . ($metainfo->{text} // "NULL") . "\n";

                if (ref($metainfo->{images}) eq 'ARRAY') {
                    my $image_count = scalar @{$metainfo->{images}};
                    print "  Metainfo.images count: $image_count\n";

                    # Download and save images
                    my $i = 0;
                    foreach my $image_url (@{$metainfo->{images}}) {
                        $i++;
                        printf "  Image %d: %s\n", $i, $image_url;

                        # Extract filename
                        my $filename = "test_images/track_${track_id}_image${i}.jpg";
                        download_image($ua, $image_url, $filename);
                    }
                } else {
                    print "  Metainfo.images is not an array (type: " . ref($metainfo->{images}) . ")\n";
                }
            } else {
                print "  ERROR: Unexpected JSON structure\n";
                print "  Raw JSON: " . substr($content, 0, 200) . "...\n";
            }
        };

        if ($@) {
            print "✗ ERROR parsing JSON: $@\n";
            print "  Raw response: " . substr($content, 0, 300) . "...\n";
        }
    } else {
        print "✗ ERROR: " . $response->status_line . "\n";
    }

    print "-" x 60 . "\n\n";
}

# Helper function to download image
sub download_image {
    my ($ua, $url, $filename) = @_;
    my $img_response = $ua->get($url);

    if ($img_response->is_success) {
        # Create directory if not exists
        my $dir = dirname($filename);
        unless (-d $dir) {
            mkdir($dir) or die "Cannot create directory $dir: $!";
        }

        open my $fh, '>', $filename or die "Cannot write $filename: $!";
        print $fh $img_response->decoded_content;
        close $fh;

        print "    → Saved to $filename\n";

        # Get image info
        my $size = -s $filename;
        my $content_type = $img_response->header('Content-Type');
        print "    → Size: " . format_size($size) . ", Content-Type: $content_type\n";
    } else {
        print "    → Failed to download: " . $img_response->status_line . "\n";
    }
}

# Helper to format bytes
sub format_size {
    my ($bytes) = @_;
    if ($bytes < 1024) {
        return "$bytes B";
    } elsif ($bytes < 1024 * 1024) {
        return sprintf("%.1f KB", $bytes / 1024);
    } else {
        return sprintf("%.1f MB", $bytes / (1024 * 1024));
    }
}

print "=" x 60 . "\n";
print "Test completed\n";
print "Check test_images/ directory for downloaded images\n";
print "=" x 60 . "\n";
