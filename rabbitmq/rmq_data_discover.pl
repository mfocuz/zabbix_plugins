#!/usr/bin/perl
use LWP::UserAgent;
use Time::Local;
use JSON::XS; 

use ZabbixProxyDB;
use strict;

#################
# Configuration #
#################
my $ZABBIX_SENDER = "zabbix_sender";
my $ZABBIX_SERVER = "";
my $ZABBIX_PORT = "";
my $DB_SERVER = "";
my $DB_NAME = "";
my $DB_USER = "";
my $DB_PASSWORD = "";
my $RMQ_PORT = "15672"; 
my $RMQ_USER = "";
my $RMQ_PASS = "";
############################

my $HOST = $ARGV[0];
my $regexp = $ARGV[1];
my $apiParam = $ARGV[2];

my $jsonObj;
my $data;

my $ua = LWP::UserAgent->new;
my $json = JSON::XS->new->utf8; # my $json = JSON->new->utf8;

# Get hosts from Zabbix proxy/server with name like $HOST
# If you need to use Zabbix API:
# Func ZabbixProxyDB::get_hosts_with_name_like should be replaced
# Func should return hashref with { host_ip => hostname }
my $rmqHosts = ZabbixProxyDB::get_hosts_with_name_like($HOST,$DB_NAME,$DB_SERVER,$DB_USER,$DB_PASSWORD);

# Go through all founded RMQ hosts and try to get JSON from any 
foreach my $host (keys %$rmqHosts)
{
	my $url = "http://$RMQ_USER:$RMQ_PASS\@$host:$RMQ_PORT/api/$apiParam/";
	my $response = $ua->get($url);
	if ($response->is_success)
	{
		my $content = $response->content;
		eval { $jsonObj = $json->decode($content) }; 
		last if ($jsonObj);
	}
}

# Compile message for Zabbix LLD on the basis of $jsonObj
my $discItems = compile_discover_data($apiParam,$regexp,$jsonObj);
print $json->pretty->encode($discItems);

#########################
#	Funcs		#
#########################
sub compile_discover_data { # handler for LLD data compilation depends on #apiParam (API path)
	my ($apiParam,$regexp,$jsonObj) = @_;

	my $discItems;
	if ($apiParam eq "queues") {$discItems = compile_discover_data_queues($regexp,$jsonObj);}
	elsif ($apiParam eq "bindings") {$discItems = compile_discover_data_bindings($regexp,$jsonObj);}
	elsif ($apiParam eq "connections") {$discItems = compile_discover_data_connections($regexp,$jsonObj);}
	elsif ($apiParam eq "nodes") {$discItems = compile_discover_data_nodes($regexp,$jsonObj);}
	elsif ($apiParam eq "federation-links") {$discItems = compile_discover_data_federations($regexp,$jsonObj);}

	return $discItems;
}

#
## Data compilers for each API paths, see $discDataUnit variable for info returned to Zabbix LLD
#

sub compile_discover_data_connections
{
	my ($regexp,$jsonObj) = @_;
	
	my $data = [];
	my $params = {
		data => $data,
	};

	foreach my $conn (@$jsonObj)
	{
		my $name = $conn->{'name'};
		my $vhost = $conn->{'vhost'};
		my $node = $conn->{'node'};
		
		my $discDataUnit = {
			"{#VHOST}"	=> $vhost,
			"{#NAME}"	=> $name,
			"{#NODE}"	=> $node,
		};
	
		push @$data,$discDataUnit;
	}
	
	return $params;	
}

sub compile_discover_data_nodes
{
	my ($regexp,$jsonObj) = @_;
	
	my $data = [];
	my $params = {
			data => $data,
	};
	
	foreach my $node (@$jsonObj)
	{
		my $name = $node->{'name'};
		my $discDataUnit = {
			"{#NODENAME}" => $name,
		};
		push @$data,$discDataUnit;
	}
	
	return $params;
}

sub compile_discover_data_bindings
{
	my ($regexp,$jsonObj) = @_;
	
	my $data = [];
	my $params = {
			data => $data,
	};
	
	foreach my $queue (@$jsonObj)
	{
		next unless ($queue->{'destination'} =~ m/$regexp/);
	
		my $queueDest = $queue->{'destination'};
		my $vhost = $queue->{'vhost'};
		my @split = split(/\./,$queueDest);
		my $threshold = "$split[0]_$split[1]_exchange";

		($queue->{'source'}) ? my $queueSource = $queue->{'source'} : next;

		my $discDataUnit = {
			"{#SOURCE}"		=> $queueSource,
			"{#VHOST}"		=> $vhost,
			"{#DESTINATION}"	=> $queueDest,
			"{#THRESHOLD}"		=> $threshold,
		};

		push @$data,$discDataUnit;
	}
	
	return $params;
}
sub compile_discover_data_federations
{
	my ($regexp,$jsonObj) = @_;
	
	my $data = [];
	my $params = {
			data => $data,
	};
	
	foreach my $element (@$jsonObj)
	{
		next unless ($element->{'exchange'} =~ m/$regexp/);

		my $name = $element->{'exchange'};
		my $vhost = $element->{'vhost'};

		my $discDataUnit = {
			"{#VHOST}"		=> $vhost,
			"{#EXCHANGE}" 		=> $name,
		};
	
		push @$data,$discDataUnit;
	}

	return $params;
}

sub compile_discover_data_queues
{
	my ($regexp,$jsonObj) = @_;
	
	my $data = [];
	my $params = {
			data => $data,
	};
	
	foreach my $queue (@$jsonObj)
	{
		next unless ($queue->{'name'} =~ m/$regexp/);

		my $queueName = $queue->{'name'};
		my $vhost = $queue->{'vhost'};

		my $discDataUnit = {
			"{#VHOST}"		=> $vhost,
			"{#NAME}" 		=> $queueName,
		};
	
		push @$data,$discDataUnit;
	}

	return $params;
}

