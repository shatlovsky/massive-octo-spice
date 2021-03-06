package CIF::REST::Observables;

use Mojo::Base 'Mojolicious::Controller';
use POSIX;
use CIF qw/$Logger/;
use Data::Dumper;
use JSON::XS;

my $encoder = JSON::XS->new->convert_blessed;

sub index {
    my $self = shift;

    my $query      	= $self->param('q') || $self->param('observable');
    
    my $filters = {};
    
    foreach my $x (qw/provider otype cc confidence group limit tags application asn rdata firsttime lasttime reporttime reporttimeend/){
        $filters->{$x} = scalar $self->param($x) if $self->param($x);
    }
    
    my $res;
    if($query or scalar(keys($filters)) > 0){
        $filters->{'confidence'} = 0 unless($filters->{'confidence'});
        $Logger->debug('generating search...');
        $res = $self->cli->search({
            token      	=> scalar $self->token,
            query      	=> scalar $query,
            nolog       => scalar $self->param('nolog'),
            filters     => $filters,
        });
    } else {
        $self->render(json   => { 'message' => 'invalid query' }, status => 404 );
    }
    
    if(defined($res)){
        $Logger->debug(Dumper($res));
        if($res){
            $self->respond_to(
                json    => { text => $encoder->encode($res) },
                html    => { template => 'observables/index' },
            );
        } else {
            $self->render(json   => { 'message' => 'unauthorized' }, status => 401 );
        }
    } else {
        $self->render(json   => { 'message' => 'unknown failure' }, status => 401 );
    }
}

sub show {
    my $self  = shift;
    
    my $res = $self->cli->search({
        token      => $self->token,
        id         => $self->stash->{'observable'},
    });
    
    if(defined($res)){
        if($res){
           #$self->stash(observables => $res);
           $Logger->debug(Dumper($res));
            $self->respond_to(
                json    => { json => $res },
                html    => { template => 'observables/show' },
            );
        } else {
            $self->render(json   => { 'message' => 'unauthorized' }, status => 401 );
        }
    } else {
        $self->render(json   => { 'message' => 'unknown failure' }, status => 500 );
    }
}

sub create {
    my $self = shift;
    
    my $data    = $self->req->json();
    my $nowait  = scalar $self->param('nowait') || 0;
    
    $Logger->debug(Dumper($data));
    
    # ping the router first, make sure we have a valid key
    my $res = $self->cli->ping_write({
        token   => $self->token,
    });
    
    if($res == 0){
        $self->render(json   => { 'message' => 'unauthorized' }, status => 401 );
        return;
    }
    
    unless(@{$data}[0]->{'group'}){
        $self->render(json => { 'message' => 'Bad Request, missing group tag in one of the observables', status => 400 } );
        return;
    }
    
    if($nowait){
        $SIG{CHLD} = 'IGNORE'; # http://stackoverflow.com/questions/10923530/reaping-child-processes-from-perl
        my $child = fork();
        
    	unless (defined $child) {
    		die "fork(): $!";
    	}
    	
        if($child == 0){
            # child
            $self->_submit($data);

            exit;
        } else {
            $self->respond_to(
                json    => { json => { 'message' => 'submission accepted, processing may take time' }, status => 201 },
            );
            return;
        }
    } else {
        $res = $self->_submit($data);
    }
    
    if(defined($res)){
        if($res){
            $self->respond_to(
                json    => { json => $res, status => 201 },
            );
            $self->res->headers->add('X-Location' => $self->req->url->to_string());
            $self->res->headers->add('X-Id' => @{$res}[0]); ## TODO
        } elsif($res == -1 ){
           $self->respond_to(
                json => { json => { "error" => "timeout" }, status => 408 },
           );
        } else {
            $self->render(json   => { 'message' => 'unauthorized' }, status => 401 );
        }
    } else {
        $self->render(json   => { 'message' => 'unknown failure' }, status => 500 );
    }
}

sub _submit {
    my $self = shift;
    my $data = shift;
    
    my $res = $self->cli->submit({
        token           => $self->token,
        observables     => $data,
        enable_metadata => 1,
    });
    return $res;
}
1;
