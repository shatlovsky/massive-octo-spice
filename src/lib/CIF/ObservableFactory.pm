package CIF::ObservableFactory;

use strict;
use warnings;

use Module::PluginFinder;
use Try::Tiny;
use Carp;
use CIF qw/$Logger/;

my $finder = Module::PluginFinder->new(
    search_path => 'CIF::Observable',
    filter      => sub {
        my ($class,$data) = @_;
        $class->understands($data);
    }
);

sub new_plugin {
    my ($self,$args) = @_;
    return unless($args);
    
    #$Logger->debug('observable: '.$args->{'observable'});
    
    my ($ret,$err);
    try {
        $ret = $finder->construct($args,%{$args});
    } catch {
        $err = shift;
    };
    return $ret if($ret);
    croak($err) if($err);
    
}

1;