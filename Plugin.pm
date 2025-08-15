package Plugins::Staroe::Plugin;

# Plugin to stream audio from Staroe radio channels
#
# Released under the MIT Licence
# Written by Alexander Chernysh
# See file LICENSE for full licence details

use strict;
use utf8;
use vars qw(@ISA);
use File::Basename;
use Cwd 'abs_path';
use File::Spec;
use feature qw(fc);
use Data::Dumper;
use JSON::XS::VersionOneAndTwo;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Player::Song;
use base qw(Slim::Plugin::OPMLBased);
use URI::Escape;
use URI::Escape qw(uri_escape_utf8);
use Encode qw(encode decode);
use Encode::Guess;
our $pluginDir;
use warnings;
use HTML::TokeParser;

use constant HTTP_TIMEOUT => 15;
use constant HTTP_CACHE => 1;
use constant HTTP_EXPIRES => '1h';
use constant MIN_SEARCH_LENGTH => 3;

use constant HOST_CONFIG => {
    # su-домены → audiopedia.su
    'svidetel\.su'        => { host => 'svidetel.su',        base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=svidetel&id=' },
    'reportage\.su'       => { host => 'reportage.su',       base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=reportage&id=' },
    'theatrologia\.su'    => { host => 'theatrologia.su',    base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=theatrologia&id=' },
    'lektorium\.su'       => { host => 'lektorium.su',       base => 'http://server.audiopedia.su:8888/get_mp3_project_1.php?site=lektorium&id=' },
    'staroeradio\.ru'     => { host => 'staroeradio.ru',     base => 'http://server.audiopedia.su:8888/get_mp3_128.php?id=' },

    # world-домены → audiopedia.world
    'svidetel\.net'       => { host => 'svidetel.net',       base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=svidetel&id=' },
    'reportage\.site'     => { host => 'reportage.site',     base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=reportage&id=' },
    'theatrologia\.com'   => { host => 'theatrologia.com',   base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=theatrologia&id=' },
    'lektorium\.net'      => { host => 'lektorium.net',      base => 'http://server.audiopedia.world:8888/get_mp3_project_1.php?site=lektorium&id=' },
    'staroeradio\.com'    => { host => 'staroeradio.com',    base => 'http://server.audiopedia.world:8888/get_mp3_128.php?id=' },
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

    my %translit_map = ('"' => 'ъ',
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

    $text = lc $text;

    # processing " -> ъ
    $text =~ s/"/ъ/g;

    # processing goes from the longest sequences to the shortest
    foreach my $key (sort { length($b) <=> length($a) } keys %translit_map) {
        my $value = $translit_map{$key};
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

    my $fetch;
    $fetch = sub {

        #$log->debug("Reading local file channels.json");

        # read local file channels.json
        my $json_content;
        { 

            local $/ = undef;       #EOL symbol = undef,      

            my $file = File::Spec->catfile($pluginDir, 'channels.json');
            open my $fh, '<', $file or die "Can't open '$file': $!";
            $json_content = <$fh>;
            close $fh;
        }

        # paring JSON content
        my $json = eval { from_json($json_content) };
        _parseChannels($json->{'channels'}, $menu);
        
        # add menu item "Search"
        push @$menu, {
            name =>  string('PLUGIN_STAROE_SEARCH'),
            #type => 'search',
            id => '1',
            #name=>'Search',
            type =>'search',
        
            url => \&_searchHandler,
            image => 'plugins/Staroe/html/images/foundbroadcast2_svg.png',
            
        };
        $callback->({
            items  => $menu
        });
    };

    $fetch->();
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
# Обработчик поиска
# sub _searchHandler {
#     my (  $client, $cb, $args) = @_;

#     my $query = $args->{search};

#     # we apply transliteration if enabled
#     my $translit =  $prefs->get('translitSearch');

#     if ($translit eq 'enable') {
#         $query = _transliterate($query);
#      }
#     if (length($query) < MIN_SEARCH_LENGTH) {
#         return $cb->([]);
#     }

#     my $timestamp = time();
#     my $url ="http://" . $prefs->get('siteSelector') . "/search?q=" . uri_escape_utf8($query) . "&_=$timestamp";
#     #my $url ="http://staroeradio.ru/search?q=" . uri_escape_utf8($query) . "&_=$timestamp";

#     Slim::Networking::SimpleAsyncHTTP->new(
#         sub {
#             my $http = shift;
#             my $html = $http->content;
            
#             my @results = _parseSearchResults($html);

#             $cb->(\@results);
#         },
#         sub {
#             $log->error("Search failed");
#             $cb->([]);
#         },
#         timeout => HTTP_TIMEOUT
#     )->get($url);
# }

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

    # Создаем парсер из строки HTML
    my $p = HTML::TokeParser->new(\$html);
    unless ($p) {
        $log->error("Failed to create TokeParser");
        return ();
    }

    # Парсим HTML как поток токенов
    while (my $token = $p->get_tag('a')) {
        my $href = $token->[1]{href};
        next unless defined $href;
        # Проверяем, есть  ли в ссылке  /audio/

        next unless $href =~ m{/(?:audio|radio)/(\d+)}i;



        my ($host, $base_url);

        # Сначала проверяем случай /audio/123 или /radio/123
        if ($href =~ m{^/(?:audio|radio)/(\d+)}i) {
            my $selected_site = $prefs->get('siteSelector') || 'staroeradio.ru';

            if ($selected_site eq 'staroeradio.com') {
                $host     = 'staroeradio.com';
                $base_url = 'http://server.audiopedia.world:8888/get_mp3_128.php?id=';
            } else {
                $host     = 'staroeradio.ru';
                $base_url = 'http://server.audiopedia.su:8888/get_mp3_128.php?id=';
            }
        }
        # Иначе — ищем по домену
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
            $log->warn("Unknown host for href: $href");
            next;
        }      


        # Получаем ID из href
        my $track_id;
        if ($href =~ m{/audio/(\d+)}i) {
            $track_id = $1;
        } elsif ($href =~ m{/radio/(\d+)}i) {
            $track_id = $1;
        } else {
            $log->warn("Could not extract ID from href: $href");
            next;
        }

        # Теперь ищем div.mp3name внутри <a>
        my $title;
        while (my $inner_token = $p->get_token) {
            last if $inner_token->[0] eq 'E' && $inner_token->[1] eq 'a'; # закрываем a

            if ($inner_token->[0] eq 'S' && $inner_token->[1] eq 'div') {
                my $class = $inner_token->[2]{class} || '';
                next unless $class eq 'mp3name';

                # Теперь читаем текст до закрытия </div>
                $title = '';
                while (my $text_token = $p->get_token) {
                    last if $text_token->[0] eq 'E' && $text_token->[1] eq 'div';
                    $title .= $text_token->[1] if $text_token->[0] eq 'T';
                }
            }
        }

        next unless $title;

        # Чистим название
        $title =~ s/^\s*<b>.*?<\/b>\s*//;
        $title =~ s/\s*$$.*?$$//g;
        $title =~ s/^\s+|\s+$//g;

        # Декодируем UTF-8 (если нужно)
        $title = decode('UTF-8', $title);

        # Формируем stream URL
        my $stream_url = $base_url . $track_id;

        #Добавляем результат
        push @results, {
            name => $title,
            play => $stream_url,
            url  => $stream_url,
            title => $title,
            artist => undef,
            album  => undef,
            duration => undef,
            type => 'audio',
            description => "Аудиозапись с $host",
            image => "plugins/Staroe/html/images/foundbroadcast2_svg.png"
        };
         # Создаём Song с нужным названием

    }

    return @results;
}




# for future releases
#
# sub _checkStreamUrl {
#     my ($url128, $url32) = @_;

#     my $final_url;

#     # Создаем callback для асинхронной проверки URL
#     my $cb = sub {
#         my $http = shift;

#         my $response_code = $http->response->code;

#         if ($response_code == 200) {
#             $final_url = $url128;
#         }
#         elsif ($response_code == 404 && $url32) {
#             my $fallback_cb = sub {
#                 my $http2 = shift;
#                 if ($http2->response->code == 200) {
#                     $final_url = $url32;
#                 } else {
#                     $log->warn("Fallback URL failed too: $url32");
#                 }
#             };

#             Slim::Networking::SimpleAsyncHTTP->new($fallback_cb, $fallback_cb)->head($url32);
#         }
#         else {
#             $log->warn("Stream not found at $url128 (code: $response_code)");
#         }
#     };

#     # Выполняем HEAD-запрос на 128kbps URL
#     Slim::Networking::SimpleAsyncHTTP->new($cb, $cb)->head($url128);

#     # Так как всё асинхронно, результат будет только после завершения callback
#     return $final_url || $url128; # может быть undef, если URL недоступен
# }
# Always end with a 1 to make Perl happy
1;
