#!/usr/bin/env perl
#
# Test API with real staroeradio track_id
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $BASE_URL_WORLD = 'http://server.audiopedia.world:8888';
my $staroe_track_id = 44206;  # Real track_id from staroeradio section

print "Testing API with real staroeradio track_id: $staroe_track_id\n";
print "=" x 80 . "\n\n";

my $ua = LWP::UserAgent->new(agent => 'StaroeRadio-APITester/1.0', timeout => 30);

# Test different API endpoint variations
my @endpoints = (
    "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$staroe_track_id",
    "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&id=$staroe_track_id",
    "$BASE_URL_WORLD/getradioinfo.php?track_id=$staroe_track_id",
    "$BASE_URL_WORLD/getradioinfo.php?id=$staroe_track_id",
    "$BASE_URL_WORLD/getprjinfo.php?cmd=getMetaInfo&track_id=$staroe_track_id",
);

foreach my $url (@endpoints) {
    print "Testing: $url\n";
    print "-" x 80 . "\n";
    
    my $request = HTTP::Request->new(GET => $url);
    my $response = $ua->request($request);
    
    if ($response->is_success) {
        my $content = $response->decoded_content;
        print "✅ Status: " . $response->status_line . "\n";
        print "Content-Type: " . $response->header('Content-Type') . "\n";
        print "Content-Length: " . length($content) . " bytes\n";
        
        if (length($content) > 0) {
            print "\nResponse:\n";
            
            # Try to parse as JSON
            eval {
                my $json = decode_json($content);
                print "✅ JSON parsed successfully\n";
                print Dumper($json);
                
                if (exists $json->{Metainfo}) {
                    my $metainfo = $json->{Metainfo};
                    print "\n✅ Found Metainfo:\n";
                    
                    if (exists $metainfo->{images} && @{$metainfo->{images}} > 0) {
                        print "  Images: " . scalar(@{$metainfo->{images}}) . "\n";
                        foreach my $img (@{$metainfo->{images}}) {
                            print "    - $img\n";
                        }
                    }
                    
                    if (exists $metainfo->{text}) {
                        print "  Description: " . substr($metainfo->{text}, 0, 100) . "...\n";
                    }
                }
            };
            
            if ($@) {
                print "Not JSON or parse failed: $@\n";
                print "Raw content:\n";
                print substr($content, 0, 500) . "\n";
            }
        } else {
            print "❌ Empty response\n";
        }
    } else {
        print "❌ Status: " . $response->status_line . "\n";
    }
    
    print "\n" . "=" x 80 . "\n\n";
}

# Try the Android app endpoint pattern
print "\n" . "=" x 80 . "\n";
print "Testing Android app endpoint pattern...\n";
print "=" x 80 . "\n\n";

# Based on Android app analysis
my $android_url = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$staroe_track_id";
print "Android endpoint: $android_url\n\n";

my $android_req = HTTP::Request->new(GET => $android_url);
$android_req->header('Accept' => 'application/json');
$android_req->header('User-Agent' => 'Mozilla/5.0 (Linux; Android 10)');

my $android_resp = $ua->request($android_req);

if ($android_resp->is_success) {
    my $content = $android_resp->decoded_content;
    print "Status: " . $android_resp->status_line . "\n";
    print "Content-Type: " . $android_resp->header('Content-Type') . "\n";
    print "Content-Length: " . length($content) . " bytes\n\n";
    
    if (length($content) > 0) {
        print "Response:\n";
        print $content . "\n";
    } else {
        print "❌ Empty response\n";
    }
} else {
    print "❌ Status: " . $android_resp->status_line . "\n";
}

print "\n" . "=" x 80 . "\n";
print "CONCLUSION: API metadata endpoint may not be working on .world domain\n";
print "OR track_id format may be different\n";
print "OR endpoint requires additional parameters\n";
print "=" x 80 . "\n";
