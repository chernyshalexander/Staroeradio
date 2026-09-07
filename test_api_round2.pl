#!/usr/bin/env perl
#
# Comprehensive API Test for Staroe Radio - Round 2
# Testing both .ru and .world domains
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;

my $BASE_URL_RU = 'http://server.audiopedia.su:8888';
my $BASE_URL_WORLD = 'http://server.audiopedia.world:8888';

print "=" x 80 . "\n";
print "STAROE RADIO API TEST - ROUND 2\n";
print "Date: " . localtime() . "\n";
print "=" x 80 . "\n\n";

my $ua = LWP::UserAgent->new(
    agent => 'StaroeRadio-APITester/2.0',
    timeout => 20,
);

my @results;

# Test helper
sub test_endpoint {
    my ($url, $description) = @_;
    
    print "Testing: $description\n";
    print "URL: $url\n";
    
    my $request = HTTP::Request->new(GET => $url);
    my $response = $ua->request($request);
    
    my $result = {
        url => $url,
        description => $description,
        success => $response->is_success,
        status => $response->code,
        content_length => 0,
        has_json => 0,
        has_images => 0,
        error => undef
    };
    
    if ($response->is_success) {
        my $content = $response->decoded_content;
        $result->{content_length} = length($content);
        
        print "✅ Status: " . $response->status_line . "\n";
        print "   Content-Type: " . $response->header('Content-Type') . "\n";
        print "   Content-Length: " . length($content) . " bytes\n";
        
        if (length($content) > 0) {
            print "\n   Response preview (first 300 chars):\n";
            my $preview = substr($content, 0, 300);
            $preview =~ s/\n/\\n/g;
            print "   $preview\n";
            
            # Try to parse JSON
            eval {
                my $json = decode_json($content);
                $result->{has_json} = 1;
                print "\n   ✅ JSON parsed successfully\n";
                
                # Check for images
                if (exists $json->{Metainfo} && exists $json->{Metainfo}->{images}) {
                    my @images = @{$json->{Metainfo}->{images}};
                    if (@images) {
                        $result->{has_images} = 1;
                        $result->{image_count} = scalar(@images);
                        print "   ✅ Found " . scalar(@images) . " image(s)\n";
                        foreach my $img (@images) {
                            print "      - $img\n";
                        }
                    }
                }
                
                # Show structure
                print "\n   JSON Structure:\n";
                print "   " . Dumper($json);
            };
            
            if ($@) {
                print "\n   ⚠️  Not JSON or parse failed: $@\n";
                $result->{error} = "JSON parse failed: $@";
            }
        } else {
            print "   ❌ Empty response\n";
            $result->{error} = "Empty response";
        }
    } else {
        print "❌ Status: " . $response->status_line . "\n";
        $result->{error} = $response->status_line;
    }
    
    print "\n" . "-" x 80 . "\n\n";
    
    push @results, $result;
    return $result;
}

print "PHASE 1: Check Current Track Info (Live Stream)\n";
print "=" x 80 . "\n\n";

# Test .ru domain
print "Testing .RU domain:\n";
test_endpoint("$BASE_URL_RU/getcurrentinfo.php", ".RU - Get current track info");

# Test .world domain  
print "Testing .WORLD domain:\n";
test_endpoint("$BASE_URL_WORLD/getcurrentinfo.php", ".WORLD - Get current track info");

print "\nPHASE 2: Test Metadata API with Various Track IDs\n";
print "=" x 80 . "\n\n";

my @test_track_ids = (44206, 29144, 12345, 10000, 20000, 30000, 40000, 50000);

foreach my $track_id (@test_track_ids) {
    print "Testing track_id: $track_id\n";
    
    # Test .ru
    test_endpoint("$BASE_URL_RU/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id", 
                 ".RU - Metadata for track_id=$track_id");
    
    # Test .world
    test_endpoint("$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id",
                 ".WORLD - Metadata for track_id=$track_id");
}

print "\nPHASE 3: Test Alternative Endpoints\n";
print "=" x 80 . "\n\n";

# Try different endpoint variations
my @alternatives = (
    ["$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo&id=44206", "Using 'id' parameter"],
    ["$BASE_URL_WORLD/getradioinfo.php?track_id=44206", "No 'cmd' parameter"],
    ["$BASE_URL_WORLD/getradioinfo.php?id=44206", "Only 'id' parameter"],
    ["$BASE_URL_WORLD/getprjinfo.php?cmd=getMetaInfo&track_id=44206", "Using getprjinfo.php"],
    ["$BASE_URL_WORLD/getradioinfo.php?cmd=getMetaInfo", "No track_id parameter"],
    ["$BASE_URL_WORLD/getradioinfo.php", "No parameters at all"],
);

foreach my $alt (@alternatives) {
    test_endpoint($alt->[0], $alt->[1]);
}

print "\nPHASE 4: Summary\n";
print "=" x 80 . "\n\n";

my $total = scalar @results;
my $success = grep { $_->{success} } @results;
my $with_content = grep { $_->{content_length} > 0 } @results;
my $with_json = grep { $_->{has_json} } @results;
my $with_images = grep { $_->{has_images} } @results;

print "Total tests: $total\n";
print "Successful HTTP: $success (" . sprintf("%.1f%%", ($success/$total)*100) . ")\n";
print "With content: $with_content (" . sprintf("%.1f%%", ($with_content/$total)*100) . ")\n";
print "With JSON: $with_json (" . sprintf("%.1f%%", ($with_json/$total)*100) . ")\n";
print "With images: $with_images (" . sprintf("%.1f%%", ($with_images/$total)*100) . ")\n";

if ($with_images > 0) {
    print "\n✅✅✅ BREAKTHROUGH! Found working API with images!\n";
    
    foreach my $result (@results) {
        if ($result->{has_images}) {
            print "\nWORKING ENDPOINT:\n";
            print "  URL: " . $result->{url} . "\n";
            print "  Description: " . $result->{description} . "\n";
            print "  Images: " . $result->{image_count} . "\n";
        }
    }
} else {
    print "\n❌ Still no working API for cover images found\n";
}

print "\n" . "=" x 80 . "\n";
print "CONCLUSION:\n";
print "=" x 80 . "\n";

if ($with_images > 0) {
    print "✅ API IS WORKING! Can proceed with implementation.\n";
} elsif ($with_json > 0) {
    print "⚠️  API returns JSON but no images found. Need investigation.\n";
} elsif ($success > 0) {
    print "❌ Server responds but no valid data. API may be deprecated.\n";
} else {
    print "❌ Complete API failure. Server unreachable or service down.\n";
}

print "\nTest completed: " . localtime() . "\n";
print "=" x 80 . "\n";
