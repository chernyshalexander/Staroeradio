package Plugins::Staroe::Plugin;

# Plugin to stream audio from Staroe radio channels
#
# Released under the MIT Licence
# Written by Alexander Chernysh
# See file LICENSE for full licence details

use strict;
use utf8;
use vars qw(@ISA);
use base qw(Slim::Plugin::OPMLBased);
use feature qw(fc);

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use constant HTTP_TIMEOUT => 15;
use constant HTTP_CACHE => 1;
use constant HTTP_EXPIRES => '1h';



my $log;

# Get the data related to this plugin and preset certain variables with 
# default values in case they are not set
my $prefs = preferences('plugin.staroe');
$prefs->init({ menuLocation => 'radio', orderBy => 'popular', groupByGenre => 0, streamingQuality => 'highest', descriptionInTitle => 0, secondLineText => 'description' });

# This is the entry point in the script
BEGIN {
    # Initialize the logging
    $log = Slim::Utils::Log->addLogCategory({
        'category'     => 'plugin.staroe',
        'defaultLevel' => 'ERROR',
        'description'  => 'STAROE'#string('PLUGIN_STAROE'),
    });
}

# This is called when squeezebox server loads the plugin.
# It is used to initialize variables and the like.
sub initPlugin {
    my $class = shift;

    # Initialize the plugin with the given values. The 'feed' is the first
    # method called. The available menu entries will be shown in the new 
    # menu entry 'staroe'.
    $class->SUPER::initPlugin(
        feed   => \&_feedHandler,
        tag    => 'staroe',
        menu   => 'radios',
        is_app =>  1 ,
        weight => 10,
    );

    if (!$::noweb) {
        require Plugins::Staroe::Settings;
        Plugins::Staroe::Settings->new;
    }
}

# Called when the plugin is stopped
sub shutdownPlugin {
    my $class = shift;
}

# Returns the name to display on the squeezebox
sub getDisplayName { 'PLUGIN_STAROE' }

sub playerMenu { undef }

sub _feedHandler {
    my ($client, $callback, $args, $passDict) = @_;

    my $menu = [];

    my $fetch;
    $fetch = sub {

        $log->debug("Reading local file channels.json");

        # read local file channels.json
        my $json_content;
        {
            local $/ = undef;
            open my $fh, '<', 'plugins/Staroe/channels.json' or die "Could not open file 'channels.json' $!";
            $json_content = <$fh>;
            close $fh;
        }

        # Парсинг JSON-содержимого
        my $json = eval { from_json($json_content) };

        #if ($prefs->get('groupByGenre')) {
        #    _parseChannelsWithGroupByGenre($json->{'channels'}, $menu);
        #}
        #else {
            _parseChannels(_sortChannels($json->{'channels'}), $menu);
        #}

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
=begin comment
sub _parseChannelsWithGroupByGenre {
    my ($channels, $menu) = @_;

    my %menu_items;

    # Create submenus for each genre.
    # First check if the genre menu doesn't exist yet. If if doesn't,
    # create the menu item and let `items` reference to a (yet) empty
    # array. Then for each genre, parse the channel and add it to the
    # array. As this works by reference it can all be done in one loop.

    for my $channel (@$channels) {
        for my $genre (split('\|', $channel->{'genre'})) {
            if (!exists($menu_items{$genre})) {
                $menu_items{ $genre } = ();
                push @$menu, {
                    name => ucfirst($genre),
                    items => \@{$menu_items{$genre}}
                };
            }
            push @{ $menu_items{ $genre } }, _parseChannel($channel);
        }
    }

    # Sort items within the submenus
    foreach ( @$menu ) {
        $_->{'items'} = _sortChannels($_->{'items'}); 
    }

    # Sort the genres themselves alphabetically
    @$menu = sort { $a->{name} cmp $b->{name} } @$menu;
}

=cut

sub _parseChannel {
    my ($channel) = @_;

    return {
        name => _getFirstLineText($channel, 0),
        description => $channel->{'description'},
        listeners => $channel->{'listeners'},
        current_track => $channel->{'lastPlaying'},
        genre => (join ', ', map ucfirst, split '\|', $channel->{'genre'}), # split genre and capitalise the first letter, so 'ambient|electronic' becomes 'Ambient, Electronic'
        line1 => _getFirstLineText($channel, 1),
        line2 => _getSecondLineText($channel),
        type => 'audio',
        url => _getStream($channel),
        image => $channel->{'largeimage'}
    };
}

sub _getStream {
    my ($channel) = shift;

    my ($quality, $format) = split(':', $prefs->get('streamingQuality'));
    my $playlists = $channel->{'playlists'};
    for my $stream (@$playlists) {
        if ($stream->{'quality'} eq $quality && $stream->{'format'} eq $format) {
            $log->debug("Using stream url $stream->{'url'}");
            return $stream->{'url'};
        }
    }
    $log->warn("Could not find preferred streaming quality. Returning first result as fallback: $playlists->[0]->{'quality'}:$playlists->[0]->{'format'}");
    return $playlists->[0]->{'url'};
}

sub _sortChannels {
    my ($channels) = shift;

    my @sorted_channels;
    my $orderBy = $prefs->get('orderBy');
    if ($orderBy eq 'popular') {
        # sort by number of listeners descending
        @sorted_channels = sort { $b->{listeners} <=> $a->{listeners} } @$channels;
    }
    elsif ($orderBy eq 'title') {
        # sort alphabetically but case-insensitive
        @sorted_channels = sort { fc($a->{title}) cmp fc($b->{title}) } @$channels;
    }
    else {
        # do not sort, use order as provided in channel feed
        @sorted_channels = @$channels;
    }
    return \@sorted_channels;
}

sub _getFirstLineText {
    my ($channel, $isFirstLine) = @_;

    # Display the channel description in the title. If a skin/app supports line1/line2
    # the description is added to the title if the description is not already shown on
    # line2.
    if ($prefs->get('descriptionInTitle') && (
        ($prefs->get('secondLineText') eq 'description' && !$isFirstLine) ||
        ($prefs->get('secondLineText') ne 'description' && $isFirstLine)
        )) {
        return "$channel->{'title'}: $channel->{'description'}";
    }
    else {
        return $channel->{'title'};
    }
}

sub _getSecondLineText {
    my ($channel) = shift;

    my $secondLineText = $prefs->get('secondLineText');
    if ($secondLineText eq 'lastPlayed') {
        return $channel->{'lastPlaying'};
    }
    elsif ($secondLineText eq 'listeners') {
        return sprintf(string('PLUGIN_STAROE    _SECOND_LINE_TEXT_LISTENERS_SPRINTF', $channel->{'listeners'}));
    }
    else {
        return $channel->{'description'};
    }
}

# Always end with a 1 to make Perl happy
1;
