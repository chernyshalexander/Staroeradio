#!/usr/bin/env perl
#
# Analyze the XML structure from getcurrentinfo.php
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;

my $BASE_URL_WORLD = 'http://server.audiopedia.world:8888';

print "Analyzing XML structure from getcurrentinfo.php\n";
print "=" x 80 . "\n\n";

my $ua = LWP::UserAgent->new(agent => 'StaroeRadio-APITester/1.0', timeout => 30);

my $url = "$BASE_URL_WORLD/getcurrentinfo.php";
my $request = HTTP::Request->new(GET => $url);
my $response = $ua->request($request);

if ($response->is_success) {
    my $content = $response->decoded_content;
    
    print "✅ Successfully fetched XML\n";
    print "Content-Length: " . length($content) . " bytes\n\n";
    
    print "Full XML content:\n";
    print "=" x 80 . "\n";
    print $content . "\n";
    print "=" x 80 . "\n\n";
    
    # Analyze structure
    print "Analysis:\n";
    print "-" x 80 . "\n";
    
    # Check for detskoeradio
    if ($content =~ /<detskoeradio>(.*?)<\/detskoeradio>/s) {
        my $section = $1;
        print "\n✅ Found <detskoeradio> section:\n";
        
        if ($section =~ /<id>(\d+)<\/id>/) {
            print "  track_id: $1\n";
        }
        if ($section =~ /<name>([^<]+)<\/name>/) {
            print "  name: $1\n";
        }
        if ($section =~ /<file>([^<]+)<\/file>/) {
            print "  file: $1\n";
        }
    }
    
    # Check for staroeradio
    if ($content =~ /<staroeradio>(.*?)<\/staroeradio>/s) {
        my $section = $1;
        print "\n✅ Found <staroeradio> section:\n";
        
        if ($section =~ /<id>(\d+)<\/id>/) {
            print "  track_id: $1\n";
        }
        if ($section =~ /<name>([^<]+)<\/name>/) {
            print "  name: $1\n";
        }
        if ($section =~ /<file>([^<]+)<\/file>/) {
            print "  file: $1\n";
        }
    } else {
        print "\n❌ No <staroeradio> section found (might be empty if not currently playing)\n";
    }
    
    # Try different API endpoints
    print "\n" . "=" x 80 . "\n";
    print "Testing alternative API endpoints...\n";
    print "=" x 80 . "\n\n";
    
    # Try direct file URL from XML
    if ($content =~ /<file>([^<]+\.mp3)<\/file>/s) {
        my $filename = $1;
        print "Found file in XML: $filename\n\n";
        
        # Extract track_id patterns from different possible formats
        # Sometimes track_id is embedded in the response or we need to use file name
    }
    
    # Try the API with the detskoeradio track_id
    if ($content =~ /<detskoeradio>.*?<id>(\d+)<\/id>/s) {
        my $track_id = $1;
        print "Testing API with detskoeradio track_id: $track_id\n";
        print "-" x 80 . "\n";
        
        my $api_url = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
        my $api_req = HTTP::Request->new(GET => $api_url);
        my $api_resp = $ua->request($api_req);
        
        if ($api_resp->is_success) {
            my $api_content = $api_resp->decoded_content;
            print "Status: " . $api_resp->status_line . "\n";
            print "Content-Length: " . length($api_content) . " bytes\n";
            
            if (length($api_content) > 0) {
                print "\nResponse content:\n";
                print $api_content . "\n";
            } else {
                print "❌ Empty response\n";
            }
        } else {
            print "❌ Failed: " . $api_resp->status_line . "\n";
        }
    }
    
    # Try with 0 or empty track_id
    print "\n" . "-" x 80 . "\n";
    print "Testing API with track_id=0\n";
    print "-" x 80 . "\n";
    
    my $api_url0 = "$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=0";
    my $api_req0 = HTTP::Request->new(GET => $api_url0);
    my $api_resp0 = $ua->request($api_req0);
    
    if ($api_resp0->is_success) {
        my $api_content = $api_resp0->decoded_content;
        print "Status: " . $api_resp0->status_line . "\n";
        print "Content-Length: " . length($api_content) . " bytes\n";
        
        if (length($api_content) > 0) {
            print "\nResponse content:\n";
            print $api_content . "\n";
        } else {
            print "❌ Empty response\n";
        }
    }
    
} else {
    print "❌ Failed to fetch XML: " . $response->status_line . "\n";
}

print "\n";
