#!/usr/bin/env perl
#
# Test script for Staroe Radio API requests
# Tests API endpoints for fetching track metadata and cover images
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON::PP;  # Use JSON::PP instead of JSON::XS (comes with Perl core)
# XML::Simple not available, will parse XML manually
use HTTP::Request;
use Data::Dumper;
use File::Path qw(make_path);
use File::Basename;
use Encode qw(decode encode);

# Configuration
my $BASE_URL_RU = 'http://server.audiopedia.su:8888';
my $BASE_URL_WORLD = 'http://server.audiopedia.world:8888';
my $TEST_DIR = 'test_results';
my $IMAGES_DIR = "$TEST_DIR/images";
my $REPORT_FILE = "$TEST_DIR/api_test_report.txt";

# Create test directories
make_path($IMAGES_DIR) unless -d $IMAGES_DIR;
make_path($TEST_DIR) unless -d $TEST_DIR;

# Open report file
open(my $fh, '>', $REPORT_FILE) or die "Cannot create report file: $!";
print $fh "=" x 80 . "\n";
print $fh "Staroe Radio API Test Report\n";
print $fh "=" x 80 . "\n";
print $fh "Generated: " . localtime() . "\n\n";

# Create User Agent
my $ua = LWP::UserAgent->new(
    agent => 'StaroeRadio-APITester/1.0',
    timeout => 30,
);

# Test counters
my $test_count = 0;
my $pass_count = 0;
my $fail_count = 0;

# Track ID for testing (can be updated during tests)
my $track_id = 12345;  # Default test track_id

# Helper function to make HTTP request
sub make_request {
    my ($url, $description) = @_;

    $test_count++;
    print "\n[$test_count] Testing: $description\n";
    print "URL: $url\n";
    print $fh "\n" . "=" x 80 . "\n";
    print $fh "TEST $test_count: $description\n";
    print $fh "-" x 80 . "\n";
    print $fh "URL: $url\n";

    my $request = HTTP::Request->new(GET => $url);
    my $response = $ua->request($request);

    if ($response->is_success) {
        $pass_count++;
        my $content = $response->decoded_content;
        my $content_type = $response->header('Content-Type');
        my $content_length = length($content);

        print "✅ PASS - Status: " . $response->status_line . "\n";
        print "   Content-Type: $content_type\n";
        print "   Content-Length: $content_length bytes\n";

        print $fh "✅ PASS\n";
        print $fh "Status: " . $response->status_line . "\n";
        print $fh "Content-Type: $content_type\n";
        print $fh "Content-Length: $content_length bytes\n";

        return ($response, $content);
    } else {
        $fail_count++;
        print "❌ FAIL - Status: " . $response->status_line . "\n";

        print $fh "❌ FAIL\n";
        print $fh "Status: " . $response->status_line . "\n";
        print $fh "Error: " . $response->status_line . "\n";

        return (undef, undef);
    }
}

# Helper function to download image
sub download_image {
    my ($url, $track_id, $track_name) = @_;

    my ($response, $content) = make_request($url, "Download image for track_id=$track_id");

    if ($response && $response->is_success) {
        # Determine file extension from content type
        my $content_type = $response->header('Content-Type');
        my $ext = 'jpg';
        if ($content_type =~ /jpeg/i) {
            $ext = 'jpg';
        } elsif ($content_type =~ /png/i) {
            $ext = 'png';
        } elsif ($content_type =~ /gif/i) {
            $ext = 'gif';
        }

        # Create safe filename
        my $safe_name = $track_name;
        $safe_name =~ s/[^a-zA-Z0-9._-]/_/g;
        $safe_name =~ s/_+/_/g;
        $safe_name =~ s/^_|_$//g;
        my $filename = sprintf("%s_%04d_%s.%s", $safe_name, $track_id, $track_id, $ext);
        my $filepath = "$IMAGES_DIR/$filename";

        # Save image
        open(my $img_fh, '>', $filepath) or die "Cannot save image: $!";
        binmode $img_fh;
        print $img_fh $content;
        close $img_fh;

        print "   Saved to: $filepath\n";
        print $fh "   Saved to: $filepath\n";

        # Get image size
        my $size = -s $filepath;
        print "   File size: $size bytes\n";
        print $fh "   File size: $size bytes\n";

        return $filepath;
    }

    return undef;
}

# Helper function to print JSON structure
sub print_json_structure {
    my ($json_ref, $depth) = @_;
    $depth //= 0;
    my $indent = "  " x $depth;

    if (ref($json_ref) eq 'HASH') {
        foreach my $key (sort keys %$json_ref) {
            my $value = $json_ref->{$key};
            if (ref($value) eq 'HASH' || ref($value) eq 'ARRAY') {
                print $fh "$indent$key:\n";
                print_json_structure($value, $depth + 1);
            } else {
                my $display_value = $value;
                if (length($display_value) > 100) {
                    $display_value = substr($display_value, 0, 97) . '...';
                }
                print $fh "$indent$key: $display_value\n";
            }
        }
    } elsif (ref($json_ref) eq 'ARRAY') {
        foreach my $item (@$json_ref) {
            print_json_structure($item, $depth);
        }
    }
}

# =============================================================================
# TEST 1: Get Current Track Info (Live Stream) - .ru domain
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST 1: Get Current Track Info (Live Stream) - .ru domain\n";
print "=" x 80 . "\n";
print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUITE 1: Live Stream - Current Track Info (.ru)\n";
print $fh "=" x 80 . "\n";

my $url1 = "$BASE_URL_RU/getcurrentinfo.php";
my ($response1, $content1) = make_request($url1, "Get current track info (.ru)");

if ($response1) {
    print $fh "\nResponse Content (first 500 chars):\n";
    print $fh substr($content1, 0, 500) . "\n";

    # Parse XML manually (XML::Simple not available)
    eval {
        print $fh "\nParsing XML manually...\n";

        # Extract staroeradio section
        if ($content1 =~ /<staroeradio>\s*<id>(\d+)<\/id>\s*<name>([^<]+)<\/name>\s*<file>([^<]+)<\/file>\s*<start>([^<]+)<\/start>\s*<time>([^<]+)<\/time>\s*<\/staroeradio>/s) {
            my ($id, $name, $file, $start, $time) = ($1, $2, $3, $4, $5);

            print "\n✅ Extracted staroeradio data:\n";
            print "   track_id: $id\n";
            print "   name: " . decode('UTF-8', $name) . "\n";
            print "   file: $file\n";
            print "   start: $start\n";
            print "   time: $time\n";

            print $fh "\n✅ Extracted staroeradio data:\n";
            print $fh "   track_id: $id\n";
            print $fh "   name: " . decode('UTF-8', $name) . "\n";
            print $fh "   file: $file\n";
            print $fh "   start: $start\n";
            print $fh "   time: $time\n";

            # Update track_id for next test
            $track_id = $id if $id;
        } else {
            print "\n⚠️  Could not parse staroeradio XML section\n";
            print $fh "\n⚠️  Could not parse staroeradio XML section\n";

            # Try simpler pattern
            if ($content1 =~ /<staroeradio>\s*<id>(\d+)<\/id>/s) {
                print "✅ At least found track_id: $1\n";
                print $fh "✅ At least found track_id: $1\n";
                $track_id = $1 if $1;
            }
        }

        # Extract detskoeadio section (if exists)
        if ($content1 =~ /<detskoeadio>\s*<id>(\d+)<\/id>\s*<name>([^<]+)<\/name>/s) {
            my ($id, $name) = ($1, $2);
            print $fh "\n✅ Found detskoeadio section:\n";
            print $fh "   track_id: $id\n";
            print $fh "   name: " . decode('UTF-8', $name) . "\n";
        }
    };

    if ($@) {
        print "\n❌ Failed to parse XML: $@\n";
        print $fh "\n❌ Failed to parse XML: $@\n";
    }
}

# =============================================================================
# TEST 2: Get Track Metadata with Cover Images - .ru domain
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST 2: Get Track Metadata with Cover Images - .ru domain\n";
print "=" x 80 . "\n";
print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUITE 2: Track Metadata with Cover Images (.ru)\n";
print $fh "=" x 80 . "\n";

# Use track_id from test 1 if available, otherwise use default
# track_id is already declared globally and may have been updated in test 1

my $url2 = "$BASE_URL_RU/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
my ($response2, $content2) = make_request($url2, "Get track metadata for track_id=$track_id (.ru)");

if ($response2) {
    print $fh "\nResponse Content (first 500 chars):\n";
    print $fh substr($content2, 0, 500) . "\n";

    # Parse JSON
    eval {
        my $json = decode_json($content2);

        print $fh "\nParsed JSON Structure:\n";
        print_json_structure($json);

        if (exists $json->{Metainfo}) {
            my $metainfo = $json->{Metainfo};

            print "\n✅ Found Metainfo section\n";
            print $fh "\n✅ Found Metainfo section\n";

            if (exists $metainfo->{images} && ref($metainfo->{images}) eq 'ARRAY') {
                my @images = @{$metainfo->{images}};
                print "✅ Found " . scalar(@images) . " image(s)\n";
                print $fh "✅ Found " . scalar(@images) . " image(s)\n";

                my $image_num = 1;
                foreach my $img_url (@images) {
                    print "\n  Image $image_num: $img_url\n";
                    print $fh "\n  Image $image_num: $img_url\n";

                    # Download first image for verification
                    if ($image_num == 1) {
                        my $track_name = "test_track_" . $track_id;
                        download_image($img_url, $track_id, $track_name);
                    }

                    $image_num++;
                }
            } else {
                print "\n❌ No images array found in Metainfo\n";
                print $fh "\n❌ No images array found in Metainfo\n";
            }

            if (exists $metainfo->{text}) {
                my $text = $metainfo->{text};
                print "\n✅ Track description found\n";
                print "   Text: " . substr($text, 0, 100) . "...\n";
                print $fh "\n✅ Track description found\n";
                print $fh "Text: $text\n";
            }
        } else {
            print "\n❌ No Metainfo section found in JSON\n";
            print $fh "\n❌ No Metainfo section found in JSON\n";
        }
    };

    if ($@) {
        print "\n❌ Failed to parse JSON: $@\n";
        print $fh "\n❌ Failed to parse JSON: $@\n";
    }
}

# =============================================================================
# TEST 3: Get Track Metadata - Multiple Track IDs
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST 3: Get Track Metadata - Multiple Track IDs\n";
print "=" x 80 . "\n";
print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUITE 3: Multiple Track Metadata Requests\n";
print $fh "=" x 80 . "\n";

# Test with a few different track IDs
my @test_track_ids = (10000, 15000, 20000, 25000, 30000);

foreach my $test_id (@test_track_ids) {
    my $url = "$BASE_URL_RU/getradioinfo.php?cmd=getMetaInfo&track_id=$test_id";
    my ($resp, $cont) = make_request($url, "Get metadata for track_id=$test_id");

    if ($resp) {
        eval {
            my $json = decode_json($cont);

            if (exists $json->{Metainfo}) {
                my $metainfo = $json->{Metainfo};
                print $fh "\nTrack ID $test_id:\n";

                if (exists $metainfo->{images} && ref($metainfo->{images}) eq 'ARRAY') {
                    my @images = @{$metainfo->{images}};
                    print "✅ Track $test_id: " . scalar(@images) . " image(s)\n";
                    print $fh "  Images: " . scalar(@images) . " image(s)\n";

                    if (@images) {
                        my $img_url = $images[0];
                        print "  First image: $img_url\n";
                        print $fh "  First image: $img_url\n";

                        # Download image for verification
                        my $track_name = "track_$test_id";
                        download_image($img_url, $test_id, $track_name);
                    }
                } else {
                    print "⚠️  Track $test_id: No images\n";
                    print $fh "  No images found\n";
                }

                if (exists $metainfo->{text}) {
                    my $text = $metainfo->{text};
                    my $text_preview = substr($text, 0, 50);
                    print "  Description: $text_preview...\n";
                    print $fh "  Description: $text\n";
                }
            }
        };

        if ($@) {
            print "❌ Failed to parse JSON for track $test_id: $@\n";
            print $fh "❌ Failed to parse JSON for track $test_id: $@\n";
        }
    }
}

# =============================================================================
# TEST 4: Test .world domain (if accessible)
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST 4: Get Current Track Info - .world domain\n";
print "=" x 80 . "\n";
print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUITE 4: Live Stream - Current Track Info (.world)\n";
print $fh "=" x 80 . "\n";

my $url4 = "$BASE_URL_WORLD/getcurrentinfo.php";
my ($response4, $content4) = make_request($url4, "Get current track info (.world)");

if ($response4) {
    print $fh "\nResponse Content (first 300 chars):\n";
    print $fh substr($content4, 0, 300) . "\n";
    print "✅ .world domain is accessible\n";
    print $fh "✅ .world domain is accessible\n";
} else {
    print "⚠️  .world domain is not accessible\n";
    print $fh "⚠️  .world domain is not accessible\n";
}

# =============================================================================
# TEST 5: Test metadata endpoint on .world domain
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST 5: Get Track Metadata - .world domain\n";
print "=" x 80 . "\n";
print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUITE 5: Track Metadata (.world)\n";
print $fh "=" x 80 . "\n";

my $url5 = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
my ($response5, $content5) = make_request($url5, "Get metadata for track_id=$track_id (.world)");

if ($response5) {
    eval {
        my $json = decode_json($content5);

        if (exists $json->{Metainfo}) {
            my $metainfo = $json->{Metainfo};
            print "✅ .world metadata endpoint works\n";
            print $fh "✅ .world metadata endpoint works\n";

            if (exists $metainfo->{images} && ref($metainfo->{images}) eq 'ARRAY') {
                my @images = @{$metainfo->{images}};
                print "  Images: " . scalar(@images) . "\n";
                print $fh "  Images: " . scalar(@images) . "\n";
            }
        }
    };

    if ($@) {
        print "❌ Failed to parse .world JSON: $@\n";
        print $fh "❌ Failed to parse .world JSON: $@\n";
    }
}

# =============================================================================
# SUMMARY
# =============================================================================
print "\n" . "=" x 80 . "\n";
print "TEST SUMMARY\n";
print "=" x 80 . "\n";
print "Total tests: $test_count\n";
print "Passed: $pass_count\n";
print "Failed: $fail_count\n";
print "Success rate: " . sprintf("%.1f%%", ($pass_count / $test_count) * 100) . "\n";

print $fh "\n" . "=" x 80 . "\n";
print $fh "TEST SUMMARY\n";
print $fh "=" x 80 . "\n";
print $fh "Total tests: $test_count\n";
print $fh "Passed: $pass_count\n";
print $fh "Failed: $fail_count\n";
print $fh "Success rate: " . sprintf("%.1f%%", ($pass_count / $test_count) * 100) . "\n";

print $fh "\n" . "=" x 80 . "\n";
print $fh "Test completed: " . localtime() . "\n";
print $fh "=" x 80 . "\n";

close($fh);

print "\n✅ Test report saved to: $REPORT_FILE\n";
print "✅ Downloaded images saved to: $IMAGES_DIR/\n";

print "\n" . "=" x 80 . "\n";
print "NEXT STEPS:\n";
print "=" x 80 . "\n";
print "1. Review the test report: cat $REPORT_FILE\n";
print "2. Check downloaded images in: $IMAGES_DIR/\n";
print "3. Verify that images are relevant to the tracks\n";
print "4. Report findings to user for confirmation\n";
print "=" x 80 . "\n";
