#!/usr/bin/env perl
#
# Quick test with real track_id from live stream
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON::PP;

my $BASE_URL_WORLD = 'http://server.audiopedia.world:8888';
my $track_id = 29144;  # Real track_id from getcurrentinfo.php

print "Testing API with real track_id: $track_id\n";
print "=" x 60 . "\n\n";

my $ua = LWP::UserAgent->new(agent => 'StaroeRadio-APITester/1.0', timeout => 30);

# Test 1: Get metadata for real track_id
print "TEST 1: Get metadata for track_id=$track_id\n";
print "-" x 60 . "\n";

my $url1 = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
print "URL: $url1\n\n";

my $request1 = HTTP::Request->new(GET => $url1);
my $response1 = $ua->request($request1);

if ($response1->is_success) {
    my $content = $response1->decoded_content;
    print "✅ Status: " . $response1->status_line . "\n";
    print "Content-Type: " . $response1->header('Content-Type') . "\n";
    print "Content-Length: " . length($content) . " bytes\n\n";

    print "Response content (first 500 chars):\n";
    print substr($content, 0, 500) . "\n\n";

    if (length($content) > 0) {
        eval {
            my $json = decode_json($content);
            print "✅ Successfully parsed JSON\n\n";
            
            print "JSON Structure:\n";
            print "=" x 60 . "\n";
            
            if (exists $json->{Metainfo}) {
                my $metainfo = $json->{Metainfo};
                print "✅ Found Metainfo section\n\n";
                
                if (exists $metainfo->{images} && ref($metainfo->{images}) eq 'ARRAY') {
                    my @images = @{$metainfo->{images}};
                    print "✅ Found " . scalar(@images) . " image(s):\n";
                    my $i = 1;
                    foreach my $img (@images) {
                        print "  $i. $img\n";
                        $i++;
                    }
                    print "\n";
                } else {
                    print "❌ No images found\n\n";
                }
                
                if (exists $metainfo->{text}) {
                    my $text = $metainfo->{text};
                    print "Description: " . substr($text, 0, 200) . "...\n\n";
                }
            } else {
                print "❌ No Metainfo section found\n\n";
            }
        };
        
        if ($@) {
            print "❌ Failed to parse JSON: $@\n";
            print "Response might be HTML instead of JSON\n\n";
        }
    } else {
        print "❌ Empty response (track_id might not exist)\n\n";
    }
} else {
    print "❌ Status: " . $response1->status_line . "\n\n";
}

# Test 2: Try a few more track_ids
print "\n" . "=" x 60 . "\n";
print "TEST 2: Try multiple track IDs\n";
print "=" x 60 . "\n\n";

my @test_ids = (29144, 29145, 29146, 29140, 29150, 29000, 30000);

foreach my $test_id (@test_ids) {
    my $url = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$test_id";
    my $req = HTTP::Request->new(GET => $url);
    my $resp = $ua->request($req);
    
    if ($resp->is_success) {
        my $content = $resp->decoded_content;
        
        if (length($content) > 0) {
            eval {
                my $json = decode_json($content);
                
                if (exists $json->{Metainfo}) {
                    my $metainfo = $json->{Metainfo};
                    
                    my $has_images = (exists $metainfo->{images} && ref($metainfo->{images}) eq 'ARRAY' && @{$metainfo->{images}} > 0);
                    my $has_text = exists $metainfo->{text};
                    
                    if ($has_images || $has_text) {
                        print "✅ track_id $test_id: ";
                        print "images=" . ($has_images ? scalar(@{$metainfo->{images}}) : 0) . " ";
                        print "text=" . ($has_text ? "yes" : "no");
                        
                        if ($has_images) {
                            print " [" . $metainfo->{images}[0] . "]";
                        }
                        print "\n";
                    }
                }
            };
        }
    }
}

print "\n";
