package JMXDiscovery;

use JSON::XS;
use IO::Socket;
use strict;

my $request = "java jmx lld"; # Should be set exactly to this value, this is instraction for JMX LLD server what to do
my $zbxHeader = "ZBXD\x01";

sub new {
    my $class = shift;
    my ($jmxLLDserver, $conn, $port) = @_;
    
    my $data = {
	request => $request,
	conn => $conn,
	port => $port,
	keys => [],
	params => {regexp => ''},
    };
    
    my $self = {
        conn => $conn,
        port => $port,
        data => $data,
        jmx_lld_server => $jmxLLDserver,
    };
    
    bless $self, $class;
}

sub get_value {
    my $self = shift;
    my $keys = shift;
    
    my $request = "java gateway jmx";
    $self->{data}->{request} = $request;
    $self->{data}->{keys} = $keys;
    
    my $data = $self->request;
    
    return $data;
}

sub get_mbeans {
    my $self = shift;
    my $regexp = shift;
    
    my $request = "java jmx lld"; # Should be set exactly to this value, this is instraction for JMX LLD server what to do
    $self->{data}->{params}->{regexp} = $regexp;
    $self->{data}->{request} = $request;
    
    my $data = $self->request;
    
    return $data;
}


sub request {
    my $self = shift;
    my $request = shift;
    
    my $data = $self->{data};
    my $jmxLLDserver = $self->{jmx_lld_server};
    
    my $sock = IO::Socket::INET->new(
	PeerAddr => $jmxLLDserver,
	Proto => "tcp",
    );
    
    $data = encode_json($data);
    my $length = length($data);
    $length = pack('VCCCC',$length,0x00,0x00,0x00,0x00);
    
    $sock->send($zbxHeader.$length.$data);
    
    $sock->recv(my $header,5);
    return -1 if $header ne "ZBXD\x01";
    $sock->recv($length,8);
    $sock->recv($data, unpack('L',$length));
    
    return $data;
}

