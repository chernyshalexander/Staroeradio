#!/usr/bin/env perl
# Simple test for API getMetaInfo (without JSON module)

use strict;
use warnings;
use LWP::UserAgent;

my $api_base = "http://server.audiopedia.su:8888";
my $ua = LWP::UserAgent->new(timeout => 30);

print "=" x 60 . "\n";
print "Testing getMetaInfo API (Simple version)\n";
print "=" x 60 . "\n\n";

my @test_track_ids = (111, 222, 333, 1111);

foreach my $track_id (@test_track_ids) {
    my $url = "$api_base/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
    print "Testing track_id: $track_id\n";
    print "URL: $url\n";

    my $response = $ua->get($url);

    print "Status: " . $response->code . " " . $response->message . "\n";

    if ($response->is_success) {
        my $content = $response->decoded_content;

        # Print first 500 chars
        print "Response (first 500 chars):\n";
        print substr($content, 0, 500) . "\n";

        # Try to find JSON pattern
        if ($content =~ /\{/) {
            print "✓ Response appears to contain JSON data\n";
        } else {
            print "✗ Response doesn't appear to be JSON\n";
        }
    } else {
        print "✗ ERROR: " . $response->status_line . "\n";
    }

    print "-" x 60 . "\n\n";
}

print "=" x 60 . "\n";
print "Test completed\n";
print "=" x 60 . "\n";
