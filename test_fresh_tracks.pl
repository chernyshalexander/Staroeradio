#!/usr/bin/env perl
#
# Test API with FRESH track_id from current XML
#

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON::PP;

print "Testing API with FRESH track_id from live XML\n";
print "=" x 80 . "\n\n";

my $ua = LWP::UserAgent->new(agent => 'StaroeRadio-APITester/2.0', timeout => 20);

# Fresh track_id from the XML we just got
my @fresh_ids = (
    {id => 39225, source => 'RU - detskoeradio', name => 'Богомазов С. - Угадай-ка'},
    {id => 11041, source => 'WORLD - detskoeradio', name => 'Троепольский Г. - Белый Бим'},
    {id => 39225, source => 'RU - staroeradio (if available)', name => 'Unknown'},
    {id => 11041, source => 'WORLD - staroeradio (if available)', name => 'Unknown'},
);

my $base_ru = 'http://server.audiopedia.su:8888';
my $base_world = 'http://server.audiopedia.world:8888';

sub test_track {
    my ($track_id, $base_url, $source) = @_;
    
    my $url = "$base_url/getradioinfo.php?cmd=getMetaInfo&track_id=$track_id";
    
    print "Testing track_id=$track_id from $source\n";
    print "URL: $url\n";
    
    my $request = HTTP::Request->new(GET => $url);
    # Try with different headers
    $request->header('Accept' => 'application/json');
    $request->header('Origin' => 'http://staroeradio.ru');
    $request->header('Referer' => 'http://staroeradio.ru/');
    
    my $response = $ua->request($request);
    
    if ($response->is_success) {
        my $content = $response->decoded_content;
        my $len = length($content);
        
        print "Status: " . $response->status_line . "\n";
        print "Content-Length: $len bytes\n";
        print "Content-Type: " . $response->header('Content-Type') . "\n";
        
        if ($len > 0) {
            print "\n✅✅✅ SUCCESS! Got content!\n\n";
            print "Response:\n";
            print $content . "\n\n";
            
            # Try to parse JSON
            eval {
                my $json = decode_json($content);
                print "✅ JSON parsed successfully!\n\n";
                
                if (exists $json->{Metainfo}) {
                    my $meta = $json->{Metainfo};
                    
                    if (exists $meta->{images} && @{$meta->{images}} > 0) {
                        print "🎉🎉🎉 BREAKTHROUGH! Found " . scalar(@{$meta->{images}}) . " images:\n";
                        foreach my $img (@{$meta->{images}}) {
                            print "  - $img\n";
                        }
                    } else {
                        print "⚠️  JSON has Metainfo but no images\n";
                    }
                    
                    if (exists $meta->{text}) {
                        print "Description: " . substr($meta->{text}, 0, 100) . "...\n";
                    }
                } else {
                    print "⚠️  JSON has no Metainfo section\n";
                }
            };
            
            if ($@) {
                print "⚠️  Not JSON: $@\n";
            }
        } else {
            print "❌ Empty response\n";
        }
    } else {
        print "❌ " . $response->status_line . "\n";
    }
    
    print "\n" . "-" x 80 . "\n\n";
}

print "PHASE 1: Test fresh track_id from XML\n";
print "=" x 80 . "\n\n";

# Test fresh IDs on both domains
foreach my $track_info (@fresh_ids) {
    my $base = ($track_info->{source} =~ /RU/) ? $base_ru : $base_world;
    test_track($track_info->{id}, $base, $track_info->{source});
}

print "\nPHASE 2: Try different API patterns\n";
print "=" x 80 . "\n\n";

# Try some other patterns that might work
my @patterns = (
    "$base_world/getradioinfo.php?cmd=getMetaInfo&track_id=39225",
    "$base_world/getradioinfo.php?cmd=getMetaInfo&track_id=11041",
    "$base_world/getprjinfo.php?cmd=getMetaInfo&track_id=39225",
    "$base_world/getprjinfo.php?cmd=getMetaInfo&track_id=11041",
    "$base_world/getradioinfo.php?cmd=getMetaInfo&identifier=39225",
    "$base_world/getradioinfo.php?cmd=getMetaInfo&identifier=11041",
);

foreach my $url (@patterns) {
    print "Pattern: $url\n";
    
    my $req = HTTP::Request->new(GET => $url);
    $req->header('Accept' => 'application/json, text/javascript, */*');
    $req->header('X-Requested-With' => 'XMLHttpRequest');
    
    my $resp = $ua->request($req);
    
    if ($resp->is_success) {
        my $content = $resp->decoded_content;
        my $len = length($content);
        
        print "Status: " . $resp->status_line . "\n";
        print "Length: $len bytes\n";
        
        if ($len > 0) {
            print "\n✅ Got content!\n";
            print substr($content, 0, 500) . "\n\n";
        } else {
            print "❌ Empty\n";
        }
    } else {
        print "❌ " . $resp->status_line . "\n";
    }
    
    print "-" x 80 . "\n\n";
}

print "\n" . "=" x 80 . "\n";
print "FINAL VERDICT:\n";
print "=" x 80 . "\n";

if (grep { length($_) > 0 && /SUCCESS/ } `echo`) {
    print "✅ API IS WORKING!\n";
} else {
    print "❌ API Still not functional\n";
    print "Recommendation: Proceed with HTML scraping approach\n";
}
