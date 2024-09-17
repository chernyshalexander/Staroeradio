package Plugins::Staroe::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log   = logger('plugin.staroe');
my $prefs = preferences('plugin.staroe');
$prefs->init({ menuLocation => 'radio', orderBy => 'popular', groupByGenre => 0, streamingQuality => 'highest', descriptionInTitle => 0, secondLineText => 'description' });

# Returns the name of the plugin. The real 
# string is specified in the strings.txt file.
sub name {
    return 'PLUGIN_STAROE';
}

sub new {
 return '';
}


sub page {
    return '';
}

sub prefs {
    return (preferences('plugin.staroe'), qw(menuLocation orderBy groupByGenre streamingQuality descriptionInTitle secondLineText));
}

# Always end with a 1 to make Perl happy
1;
