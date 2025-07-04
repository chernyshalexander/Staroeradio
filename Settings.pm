package Plugins::Staroe::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log   = logger('plugin.staroe');
my $prefs = preferences('plugin.staroe');
#$prefs->init({ menuLocation => 'radio',  streamingQuality => 'highest', descriptionInTitle => 0, secondLineText => 'description',translitSearch =>1 });

# Returns the name of the plugin. The real 
# string is specified in the strings.txt file.
sub name {
    return 'PLUGIN_STAROE';
}


sub page {
    return 'plugins/Staroe/settings/basic.html';
}

sub prefs {
    return ($prefs, qw(menuLocation streamingQuality descriptionInTitle secondLineText translitSearch));
}

# Always end with a 1 to make Perl happy
1;
