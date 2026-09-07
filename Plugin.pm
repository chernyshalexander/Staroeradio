package Plugins::Staroe::Plugin;

# Plugin to stream audio from Staroe radio channels
#
# Released under the MIT Licence
# Written by Alexander Chernysh
# See file LICENSE for full licence details

use strict;
use utf8;
use File::Spec;
use JSON::XS::VersionOneAndTwo;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;
use base qw(Slim::Plugin::OPMLBased);
use URI::Escape qw(uri_escape_utf8);
use Encode qw(decode);
use HTML::Entities qw(decode_entities);
our $pluginDir;
my $cachedChannels;

# Track page data (cover + correct title/artist), cached in Slim::Utils::Cache
my $metaStore;
my @translitKeys;
my %translitMap = (
    '"' => 'ъ',
    'zh' => 'ж', 'kh' => 'х', 'ts' => 'ц',
    'ch' => 'ч', 'sh' => 'ш', 'shch' => 'щ',
    'ya' => 'я', 'yu' => 'ю', 'yo' => 'ё',
    'eh' => 'э', 'iy'=> 'ий', '\'' => 'ь',
    'a' => 'а', 'b' => 'б', 'v' => 'в',
    'g' => 'г', 'd' => 'д', 'e' => 'е',
    'z' => 'з', 'i' => 'и', 
    'k' => 'к', 'l' => 'л', 'm' => 'м',
    'n' => 'н', 'o' => 'о', 'p' => 'п',
    'r' => 'р', 's' => 'с', 't' => 'т',
    'u' => 'у', 'f' => 'ф', 'y' => 'ы'
);
use warnings;
use HTML::TokeParser;

use constant HTTP_TIMEOUT => 15;
use constant HTTP_CACHE => 1;
use constant HTTP_EXPIRES => '1h';
use constant MIN_SEARCH_LENGTH => 3;
use constant TRACK_PAGE_CACHE_EXPIRES => '1 day';
use constant COVER_CACHE_EXPIRES => '30 days';
use constant COVER_ROTATE_INTERVAL => 30;   # seconds between covers of one track
use constant LIVE_POLL_INTERVAL => 30;      # seconds between getcurrentinfo.php polls

use constant HOST_CONFIG => {
    # su-домены → audiopedia.su
    'svidetel\.su'        => { host => 'svidetel.su',        name => 'Свидетель',   base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=svidetel&id=' },
    'reportage\.su'       => { host => 'reportage.su',       name => 'Репортаж',    base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=reportage&id=' },
    'theatrologia\.su'    => { host => 'theatrologia.su',    name => 'Театрология', base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=theatrologia&id=' },
    'lektorium\.su'       => { host => 'lektorium.su',       name => 'Лекториум',   base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=lektorium&id=' },
    #'staroeradio\.ru'     => { host => 'staroeradio.ru',     base => 'http://server.audiopedia.su:8888/get_mp3_radio_128.php?id=' },

    # world-домены → audiopedia.world
    'svidetel\.net'       => { host => 'svidetel.net',       name => 'Свидетель',   base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=svidetel&id=' },
    'reportage\.site'     => { host => 'reportage.site',     name => 'Репортаж',    base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=reportage&id=' },
    'theatrologia\.com'   => { host => 'theatrologia.com',   name => 'Театрология', base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=theatrologia&id=' },
    'lektorium\.net'      => { host => 'lektorium.net',      name => 'Лекториум',   base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=lektorium&id=' },
    #'staroeradio\.com'    => { host => 'staroeradio.com',    base => 'http://server.audiopedia.world:8888/get_mp3_radio_128.php?id=' },
};

# Get the data related to this plugin and preset certain variables with 
# default values in case they are not set
my $prefs = preferences('plugin.staroe');

my $log;


# This is the entry point in the script
BEGIN {
    $pluginDir = $INC{"Plugins/Staroe/Plugin.pm"};
    $pluginDir =~ s/Plugin.pm$//; 
}
    # Initialize the logging
    $log = Slim::Utils::Log->addLogCategory({
        'category'     => 'plugin.staroe',
        'defaultLevel' => 'DEBUG',
        'description'  => string('PLUGIN_STAROE'),
    });


#
#
sub _transliterate {
    my ($text) = @_;

    $text = lc $text;

    # processing goes from the longest sequences to the shortest
    foreach my $key (@translitKeys) {
        my $value = $translitMap{$key};
        $text =~ s/\Q$key\E/$value/g;
    }

    return $text;
}


# This is called when squeezebox server loads the plugin.
# It is used to initialize variables and the like.
sub initPlugin {
    my $class = shift;
    $prefs->init({ menuLocation => 'radio',  
                    streamingQuality => 'highest', 
                    descriptionInTitle => 0, 
                    secondLineText => 'description',
                    translitSearch=>'disable', 
                    siteSelector=>'staroeradio.ru'
                    });
    Slim::Utils::Strings::loadFile(File::Spec->catfile($pluginDir, 'strings.txt'));
    # Initialize the plugin with the given values. The 'feed' is the first
    # method called. The available menu entries will be shown in the new 
    # menu entry 'staroe'.
    $class->SUPER::initPlugin(
        feed   => \&_feedHandler,
        tag    => 'staroe',
        menu   => 'radios',
        is_app => $class->can('nonSNApps') && ($prefs->get('menuLocation') eq 'apps') ? 1 : undef, 
        weight => 10,
    );

    # Pre-sort transliteration keys
    @translitKeys = sort { length($b) <=> length($a) } keys %translitMap;

    # Provide track covers and correct titles for stream URLs: archive files
    # (get_mp3...) and live streams (the m3u resolves to ...:8000/ices128 etc.)
    require Slim::Formats::RemoteMetadata;
    Slim::Formats::RemoteMetadata->registerProvider(
        match => qr{/get_mp3|/(?:ices|detskoe|music)\d*(?:\.m3u)?$},
        func  => \&_metadataProvider,
    );

    # Pre-load channels
    my $file = File::Spec->catfile($pluginDir, 'channels.json');
    if (open my $fh, '<', $file) {
        local $/ = undef;
        my $json_content = <$fh>;
        close $fh;
        my $json = eval { from_json($json_content) };
        $cachedChannels = $json->{'channels'} if $json;
    }
    $log->error("Failed to load/parse channels.json: $@") if !$cachedChannels;

    if (!$::noweb) {
        require Plugins::Staroe::Settings;
        Plugins::Staroe::Settings->new;
    }

}

sub isRemote { 1 }    
# Called when the plugin is stopped
sub shutdownPlugin {
    my $class = shift;
}

# Returns the name to display on the squeezebox
sub getDisplayName {'PLUGIN_STAROE' }

sub playerMenu { undef }

sub _feedHandler {
    my ($client, $callback, $args, $passDict) = @_;

    my $menu = [];

    if ($cachedChannels) {
        _parseChannels($cachedChannels, $menu);
    }

    # add menu item "Search"
    push @$menu, {
        name  => string('PLUGIN_STAROE_SEARCH'),
        id    => '1',
        type  => 'search',
        url   => \&_searchHandler,
        image => 'plugins/Staroe/html/images/foundbroadcast2_svg.png',
    };

    $callback->({
        items => $menu
    });
}

sub _parseChannels {
    my ($channels, $menu) = @_;
    
    for my $channel (@$channels) {
        push @$menu, _parseChannel($channel);
    }
}


sub _parseChannel {
    my ($channel) = @_;

    return {
        name => _getFirstLineText($channel, 0),
        description => $channel->{'description'},      
        
        line1 => _getFirstLineText($channel, 1),
        line2 => _getSecondLineText($channel),
        type =>'audio',
        url => _getStream($channel),
        image => $channel->{'image'}
    };
}

sub _getStream {
    my ($channel) = shift;
    my $result;    my ($quality, $format) = split(':', $prefs->get('streamingQuality'));
    my $playlists = $channel->{'playlists'};
    for my $stream (@$playlists) {
        if ($stream->{'quality'} eq $quality && $stream->{'format'} eq $format) {
            #$log->debug("Using stream url $stream->{'url'}");

            return "http://" . $prefs->get('siteSelector') .  $stream->{'url'};
        }
    }
    $log->warn("Could not find preferred streaming quality. Returning first result as fallback: $playlists->[0]->{'quality'}:$playlists->[0]->{'format'}");
    return "http://" . $prefs->get('siteSelector') . $playlists->[0]->{'url'};
}


sub _getFirstLineText {
    my ($channel) = shift;
    # my ($channel, $isFirstLine) = @_;

    # # Display the channel description in the title. If a skin/app supports line1/line2
    # # the description is added to the title if the description is not already shown on
    # # line2.
    # if ($prefs->get('descriptionInTitle') && (
    #     ($prefs->get('secondLineText') eq 'description' && !$isFirstLine) ||
    #     ($prefs->get('secondLineText') ne 'description' && $isFirstLine)
    #     )) {
    #     return "$channel->{'title'}: $channel->{'description'}";
    # }
    # else {
        return $channel->{'title'};
    # }
}

sub _getSecondLineText {
    my ($channel) = shift;

    # my $secondLineText = $prefs->get('secondLineText');
    # if ($secondLineText eq 'lastPlayed') {
    #     return $channel->{'lastPlaying'};
    # }
    # elsif ($secondLineText eq 'listeners') {
    #     return sprintf(string('PLUGIN_STAROE    _SECOND_LINE_TEXT_LISTENERS_SPRINTF', $channel->{'listeners'}));
    # }
    # else {
        return $channel->{'description'};
    # }
}

# --- Track cover art support ---------------------------------------------

# Extract track id from stream URLs like .../get_mp3_radio_128.php?id=8537
sub _trackIdFromUrl {
    my ($url) = @_;
    return $url =~ /[?&]id=(\d+)/ ? $1 : undef;
}

# The site (project host) a stream URL belongs to, e.g. lektorium.su;
# falls back to the configured main site for the radio archive streams
sub _hostFromUrl {
    my ($url) = @_;

    for my $cfg (values %{HOST_CONFIG()}) {
        return $cfg->{host} if index($url, $cfg->{base}) == 0;
    }

    return $prefs->get('siteSelector') || 'staroeradio.ru';
}

# Human-readable site name, used as the fallback artist for project tracks
sub _siteName {
    my ($site) = @_;

    for my $cfg (values %{HOST_CONFIG()}) {
        return $cfg->{name} if $cfg->{host} eq $site;
    }

    return 'Старое радио';
}

# The API server matching the configured site
sub _apiServer {
    return ($prefs->get('siteSelector') || '') eq 'staroeradio.com'
        ? 'server.audiopedia.world:8888'
        : 'server.audiopedia.su:8888';
}

# --- Live streams (Vintage / Children's radio) ----------------------------

sub _isLiveUrl {
    my ($url) = @_;
    return $url =~ m{/(?:ices|detskoe|music)\d*(?:\.m3u)?$}i;
}

# Which section of the getcurrentinfo.php answer corresponds to this stream
sub _liveSection {
    my ($url) = @_;
    return $url =~ m{/detskoe}i ? 'detskoeradio'
         : $url =~ m{/ices}i    ? 'staroeradio'
         :                        undef;
}

# Shared persistent cache instance
sub _cache {
    $metaStore ||= Slim::Utils::Cache->new;
    return $metaStore;
}

# Track page data for a site+track id: undef = not fetched yet, '' = page had
# nothing useful, otherwise { cover => ..., title => ..., artist => ... }
sub _getMeta {
    my ($site, $track_id) = @_;

    return _cache()->get("staroe_meta_$site/$track_id");
}

sub _storeMeta {
    my ($site, $track_id, $meta) = @_;

    _cache()->set("staroe_meta_$site/$track_id", $meta, COVER_CACHE_EXPIRES);
}

# Metadata provider registered for our stream URLs: serves the cover and the
# correct (site-provided) title/artist once parsed, and kicks off parsing on
# the first request. This also overrides the ID3 tags of archive files, which
# are often written in CP1251 and show up as mojibake. Works for any playback
# source (menu, CLI, favorites) since the UI always asks for metadata.
sub _metadataProvider {
    my ($client, $url) = @_;

    return _liveMetadata($client, $url) if _isLiveUrl($url);

    my $track_id = _trackIdFromUrl($url) or return {};
    my $site = _hostFromUrl($url);

    my $meta = _getMeta($site, $track_id);
    if (!defined $meta) {
        # Nothing known yet - fetch asynchronously; the newmetadata
        # notification on completion makes the UI ask again
        _fetchTrackCover($client, $site, $track_id);
        return {};
    }

    my %out;
    my $cover = $meta->{cover};
    if ($client && $meta->{covers} && @{$meta->{covers}} > 1) {
        $cover = _armCoverRotation($client, $url, $meta->{covers});
    }
    $out{cover} = $out{icon} = $cover if $cover;
    $out{title}  = $meta->{title}  if $meta->{title};
    $out{artist} = $meta->{artist} if $meta->{artist};
    return \%out;
}

# Cycle through multiple covers of the playing track: pick the current one
# and rotate it every COVER_ROTATE_INTERVAL seconds. State lives in the
# song's pluginData, so it dies with the song.
sub _armCoverRotation {
    my ($client, $url, $covers) = @_;

    my $song = $client->playingSong() or return $covers->[0];

    my $state = $song->pluginData('staroeCovers');
    if (!$state || $state->{url} ne $url) {
        $state = { url => $url, covers => $covers, i => 0 };
        $song->pluginData('staroeCovers' => $state);

        # Arm the rotation once per song; _rotateCover keeps it going.
        # setTimer() adds a new timer every call, so arm it only here.
        Slim::Utils::Timers::killTimers($client, \&_rotateCover);
        Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + COVER_ROTATE_INTERVAL, \&_rotateCover);
    }

    return $state->{covers}[$state->{i} % scalar @{$state->{covers}}];
}

sub _rotateCover {
    my ($client) = @_;

    # no rotation while paused; also stops the chain when the song is gone
    return unless $client->isPlaying();

    my $song = $client->playingSong() or return;
    my $state = $song->pluginData('staroeCovers') or return;

    $state->{i} = ($state->{i} + 1) % scalar @{$state->{covers}};
    Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + COVER_ROTATE_INTERVAL, \&_rotateCover);
}

# Live streams show the artwork of the track the station is currently
# playing, learned by polling getcurrentinfo.php every LIVE_POLL_INTERVAL
sub _liveMetadata {
    my ($client, $url) = @_;

    return {} unless $client;

    _armLivePoll($client);

    my $state = $client->pluginData('staroeLive');
    return {} unless $state && $state->{id};

    my $site = $prefs->get('siteSelector') || 'staroeradio.ru';
    my $meta = _getMeta($site, $state->{id});
    if (!defined $meta) {
        # Page not parsed yet - fetch it; newmetadata will fire on completion
        _fetchTrackCover($client, $site, $state->{id});
        return {};
    }

    my %out;
    my $cover = $meta->{cover};
    # Rotation key includes the track id: live songs persist across tracks
    my $rot_key = "$url#$state->{id}";
    if ($meta->{covers} && @{$meta->{covers}} > 1) {
        $cover = _armCoverRotation($client, $rot_key, $meta->{covers});
    }
    $out{cover} = $out{icon} = $cover if $cover;
    $out{title}  = $meta->{title}  if $meta->{title};
    $out{artist} = $meta->{artist} if $meta->{artist};
    return \%out;
}

sub _armLivePoll {
    my ($client) = @_;

    return if $client->pluginData('staroeLivePoll');
    $log->debug("Live metadata requested - arming poller");
    $client->pluginData('staroeLivePoll' => 1);
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&_livePoll);
}

sub _livePoll {
    my ($client) = @_;

    $client->pluginData('staroeLivePoll' => undef);

    # Keep the chain while a song is loaded - the client may still be
    # connecting (and thus not "playing") when the first poll fires
    my $song = $client->playingSong() or return;

    $client->pluginData('staroeLivePoll' => 1);

    my $url = eval { $song->currentTrack->url } || '';
    my $section = _liveSection($url);

    $log->debug("Live poll: url=$url section=", $section // 'undef');

    if (!$section) {
        # Not a live stream after all - poll again in case the URL resolves later
        Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + LIVE_POLL_INTERVAL, \&_livePoll);
        return;
    }

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my ($id) = $http->content =~ /<$section><id>(\d+)<\/id>/;
            $log->debug("Live poll: current id=", $id // 'not found');
            _onLiveInfo($client, $id) if $id;
        },
        sub {
            $log->debug("Live poll: fetch failed");
            # ignore fetch errors, just keep polling
        },
        { timeout => HTTP_TIMEOUT },
    )->get("http://" . _apiServer() . "/getcurrentinfo.php");

    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + LIVE_POLL_INTERVAL, \&_livePoll);
}

sub _onLiveInfo {
    my ($client, $id) = @_;

    my $state = $client->pluginData('staroeLive') || {};
    if ($state->{id} == $id) {
        $log->debug("Live: id $id unchanged");
        return;   # nothing changed since the last poll
    }

    $log->debug("Live: track changed to id $id");
    $client->pluginData('staroeLive' => { id => $id });

    my $site = $prefs->get('siteSelector') || 'staroeradio.ru';
    my $meta = _getMeta($site, $id);
    _fetchTrackCover($client, $site, $id) unless defined $meta;

    Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
}

# Track ids with a page fetch in progress
my %fetchingCover;

# Fetch the track page and store cover + title/artist from it
sub _fetchTrackCover {
    my ($client, $site, $track_id) = @_;

    return unless $site && $track_id;

    my $key = "$site/$track_id";
    return if $fetchingCover{$key} || defined _getMeta($site, $track_id);
    $fetchingCover{$key} = 1;

    my $page_url = "https://$site/audio/$track_id";

    my $done = sub { delete $fetchingCover{$key} };

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my $meta = _parseTrackPage($http->content, $site);

            if ($meta && %$meta) {
                _storeMeta($site, $track_id, $meta);
                $log->debug("Meta for track $track_id: ", join ', ',
                    map { "$_=" . ($meta->{$_} // '') } sort keys %$meta);
            }
            else {
                # Remember the absence so the page is not re-parsed on every request
                _cache()->set("staroe_meta_$site/$track_id", '', '1 day');
                $log->warn("No usable data on track page $page_url");
            }

            $done->();
            if ($client && $client->playingSong()) {
                Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
            }
        },
        sub {
            $log->warn("Failed to fetch track page $page_url for cover art");
            $done->();
        },
        {
            timeout => HTTP_TIMEOUT,
            cache   => HTTP_CACHE,
            expires => TRACK_PAGE_CACHE_EXPIRES,
        }
    )->get($page_url);
}

# Parse a track page into { cover, covers, title, artist }. Images live in
# <div class="images"><a href="BIG.jpg"><img src="SMALLs.jpg"></a>...</div>;
# all of them are collected (big linked images first, thumbnail fallbacks
# after) so they can be rotated during playback. The name is in <h1> or
# <title> and is always proper UTF-8, unlike the file's ID3 tags.
sub _parseTrackPage {
    my ($html, $site) = @_;

    return undef unless defined $html;

    my %meta;

    my $p = HTML::TokeParser->new(\$html) or return undef;

    while (my $token = $p->get_tag('div')) {
        my $class = $token->[1]{class} || '';
        next unless $class eq 'images';

        my (@big, @small);
        while (my $inner = $p->get_token) {
            last if $inner->[0] eq 'E' && $inner->[1] eq 'div';

            if ($inner->[0] eq 'S' && $inner->[1] eq 'a') {
                my $href = $inner->[2]{href};
                if ($href && $href =~ /\.(?:jpe?g|png|gif)$/i) {
                    push @big, _absoluteImageUrl($href, $site);
                }
            }

            if ($inner->[0] eq 'S' && $inner->[1] eq 'img') {
                my $src = $inner->[2]{src};
                if ($src && $src =~ /\.(?:jpe?g|png|gif)$/i) {
                    # Thumbnails carry a trailing "s" before the extension
                    $src =~ s/s(\.(?:jpe?g|png|gif))$/$1/i;
                    push @small, _absoluteImageUrl($src, $site);
                }
            }
        }

        my %seen;
        my @covers = grep { !$seen{$_}++ } (@big ? @big : @small);
        $meta{covers} = \@covers if @covers;
        last;
    }

    $meta{cover} = $meta{covers}[0] if $meta{covers};
    # Name comes from <h1> (clean, no site suffix), <title> is the fallback.
    # The artist is the leading "Artist - " part; some sites (theatrologia)
    # put it only in <title>, so fall back to that.
    my $title_text;
    if ($html =~ m{<title>([^<]+)</title>}) {
        my $raw = decode_entities($1);
        $title_text = eval { decode('UTF-8', $raw) } || $raw;
        $title_text =~ s/\s*\|\s*[^|]*$//;   # drop the trailing " | Лекториум" etc.
        $title_text =~ s/^\s+|\s+$//g;
    }
    my $name;
    if ($html =~ m{<h1[^>]*>([^<]+)</h1>}) {
        my $raw = decode_entities($1);
        $name = eval { decode('UTF-8', $raw) } || $raw;
        $name =~ s/^\s+|\s+$//g;
    }
    $name = $title_text unless $name;

    if ($name) {
        if ($name =~ s/^(.+?)\s+-\s+//) {
            $meta{artist} = $1;
        }
        elsif ($title_text && $title_text =~ s/^(.+?)\s+-\s+//) {
            $meta{artist} = $1;
        }
        else {
            $meta{artist} = _siteName($site);
        }
        $meta{title} = $name;
    }

    return \%meta;
}

sub _absoluteImageUrl {
    my ($url, $site) = @_;

    return $url if $url =~ m{^https?://}i;
    return "https://" . ($site || 'staroeradio.ru') . $url;
}

# --------------------------------------------------------------------------


sub _searchHandler {
    my (  $client, $cb, $args) = @_;
    my $query = $args->{search};

    # we apply transliteration if enabled
    my $translit =  $prefs->get('translitSearch');
    if ($translit eq 'enable') {
        $query = _transliterate($query);
     }
    if (length($query) < MIN_SEARCH_LENGTH) {
        return $cb->([]);
    }

    my $timestamp = time();
    my $url = "http://" . $prefs->get('siteSelector') . "/search?q=" . uri_escape_utf8($query) . "&_=$timestamp";

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my $html = $http->content;
            my @results = _parseSearchResults($html);
            $cb->(\@results);
        },
        sub {
            $log->error("Search failed");
            $cb->([]);
        },
        {   
            timeout => HTTP_TIMEOUT,
            cache   => HTTP_CACHE,
            expires => HTTP_EXPIRES,
        }
    )->get($url);
}


sub _parseSearchResults {
    my ($html) = @_;

    my @results;

    # Create parser from HTML string
    my $p = HTML::TokeParser->new(\$html);
    unless ($p) {
        $log->error("Failed to create TokeParser");
        return ();
    }

    my $selected_site = $prefs->get('siteSelector') || 'staroeradio.ru';
    my $is_world = ($selected_site eq 'staroeradio.com');

    # Parse HTML as a stream of tokens
    while (my $token = $p->get_tag('a')) {
        my $href = $token->[1]{href};
        next unless defined $href;

        # Check for /audio/ or /radio/
        next unless $href =~ m{/(?:audio|radio)/(\d+)}i;
        my $track_id = $1;

        my ($host, $base_url);

        # Check for direct match
        if ($href =~ m{^/(?:audio|radio)/(\d+)}i) {
            $host = $is_world ? 'staroeradio.com' : 'staroeradio.ru';
            $base_url = $is_world 
                ? 'http://server.audiopedia.world:8888/get_mp3_radio_128.php?id='
                : 'http://server.audiopedia.su:8888/get_mp3_radio_128.php?id=';
        }
        else {
            for my $pattern (keys %{HOST_CONFIG()}) {
                if ($href =~ /$pattern/i) {
                    my $cfg = HOST_CONFIG->{$pattern};
                    $host     = $cfg->{host};
                    $base_url = $cfg->{base};
                    last;
                }
            }
        }

        if (!$host) {
            # Default to staroeradio
            $host = $is_world ? 'staroeradio.com' : 'staroeradio.ru';
            $base_url = $is_world 
                ? 'http://server.audiopedia.world:8888/get_mp3_radio_128.php?id='
                : 'http://server.audiopedia.su:8888/get_mp3_radio_128.php?id=';
        }

        # Find div.mp3name inside <a>
        my $title;
        while (my $inner_token = $p->get_token) {
            last if $inner_token->[0] eq 'E' && $inner_token->[1] eq 'a';

            if ($inner_token->[0] eq 'S' && $inner_token->[1] eq 'div') {
                my $class = $inner_token->[2]{class} || '';
                next unless $class eq 'mp3name';

                $title = '';
                while (my $text_token = $p->get_token) {
                    last if $text_token->[0] eq 'E' && $text_token->[1] eq 'div';
                    $title .= $text_token->[1] if $text_token->[0] eq 'T';
                }
                last; 
            }
        }

        next unless $title;

        # Clean title
        $title =~ s/^\s*<b>.*?<\/b>\s*//;
        $title =~ s/\s*$$.*?$$//g;
        $title =~ s/^\s+|\s+$//g;

        # Decode UTF-8
        $title = decode('UTF-8', $title);

        my $stream_url = $base_url . $track_id;
        my $meta = _getMeta($host, $track_id);
        my $cover = $meta ? $meta->{cover} : undef;

        push @results, {
            name        => $title,
            title       => $title,
            artist      => _siteName($host),
            play        => $stream_url,
            url         => $stream_url,
            type        => 'audio',
            duration    => 0,
            image       => $cover || "plugins/Staroe/html/images/foundbroadcast2_svg.png",
            description => "Аудиозапись с $host",
        };
    }

    return @results;
}

# Always end with a 1 to make Perl happy
1;
