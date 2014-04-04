#!/usr/bin/perl

use LWP::UserAgent;
use Time::Local;
use Sys::Hostname;
use JSON::XS; # JSON can be used here

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

my $host = $ARGV[0];

my %jsonObj;
my @rmqParams;
my $hostName;
my $dataFile = "/tmp/$$-rmq-metrics";

open DATA_FILE, '>', $dataFile or die "Cannot open file \'$dataFile\'\n";

my $ua = LWP::UserAgent->new;
my $json = JSON::XS->new->utf8; # in case using JSON replace this string with
#my $json = JSON->new->utf8;

# Get hosts from Zabbix proxy/server with name like $host
# If you need to use Zabbix API:
# Func ZabbixProxyDB::get_hosts_with_name_like should be replaced
# Func should return hashref with { host_ip => hostname } 
my $rmqHosts = ZabbixProxyDB::get_hosts_with_name_like($host,$DB_NAME,$DB_SERVER,$DB_USER,$DB_PASSWORD);
# Get items for <hostname>
# Func ZabbixProxyDB::get_hosts_with_name_like should be replaced
# Func should return hashref with { item_key => anything }, anything - because of some bad coding practice in ZabbixProxyDB.pm ;)
my $items = ZabbixProxyDB::get_items_for_host($host,$DB_NAME,$DB_SERVER,$DB_USER,$DB_PASSWORD);

# Collect data
my $jsonObj = build_json_object($rmqHosts,$items);

# Go through all item's keys for specified <hostname> and get/calculate value for it
foreach my $key (keys %$items)
{
	$key =~ m/^(.+)\[([^:]+):([^:]+):([^\]]+)\]\[*(.*)\]*/;
	my $metric = $1;
	my $type = $2;
	my $rmqPath = $3;
	my $elementId = "$2:$3:$4";
	
	my $value;
	
	# For "aggregated" values
	if ($key =~ m/^.+\[aggregated:[^:]+:([^\]]+)\]\[*([^\]]*)\]*/) {
		my $func = $1;
		my $conditions = $2;
		my $json = $jsonObj->{$rmqPath};
		$value = calc_aggr($json,$metric,$func,$conditions);
		print DATA_FILE "$host $key $value\n";
#		print "$host $key $value\n";
	}
	# For simple values
	else {
		my $json = $jsonObj->{$rmqPath}->{$elementId};
		$value = get_value_from_json($json,$metric);
		if ($metric eq "idle_since") { ($value ne "") ? $value = convert_to_epoch($value) : $value = time;} # Only for idle_since timestamp
		print DATA_FILE $host." $key "." $value\n";
		print "$host $key $value\n";
	}
}

# Send data to Zabbix
my $cmdLine = $ZABBIX_SENDER.' -z '.$ZABBIX_SERVER.' -p '.$ZABBIX_PORT.' -i '. $dataFile;
system($cmdLine);
unlink ($dataFile);


#########
# Funcs #
#########
sub calc_aggr #func is used when key word "aggregated" found
{
	my ($json,$metric,$func,$conditions) = @_;
	
	my $result = 0;
	$conditions =~ s/"//g;
	my %conditions = map{split /\=/, $_}(split /,/, $conditions);
	
	foreach my $key (keys %$json)
	{
		if (check_conditions($json->{$key},\%conditions))
		{
			$result += get_value_from_json($json->{$key},$metric) if ($func eq "sum");
			$result += 1 if ($func eq "count");
		}
	}
	
	return $result;
}

sub check_conditions #func is used when [<conditions>] found
{
	my ($params,$conditions) = @_;
	
	return 1 if (!keys %$conditions);
	
	foreach my $condition (keys %$conditions)
	{
		my $value = get_value_from_json($params,$condition);
		my $condValue = $conditions->{$condition};
		return 0 unless ($value =~ m/$condValue/);
	}
		return 1;
}

sub get_json_object_from_rmq # get JSON for specified RMQ API path
{
	my ($hosts,$param) = @_;

	my $jsonObj;
	foreach my $host (keys %$hosts)
	{
		my $url = "http://$RMQ_USER:$RMQ_PASS\@$host:$RMQ_PORT/api/$param/";
		my $response = $ua->get($url);

		if ($response->is_success)
		{
			my $content = $response->content;
			eval { $jsonObj = $json->decode($content) };
			last if ($jsonObj);
		}
	}
	
	return $jsonObj;
}

sub build_json_object # func builds hash with all unique RMQ API paths in keys and in JSON data in values
{
	my ($rmqHosts,$items) = @_;
	
	my @rmqPaths;
	my %jsonObj;
	
	foreach my $key (keys %$items)
	{	
		$key =~ m/.*\[([^:]+):([^:]+):(.*)\]/;
		my $rmqPath = $2;
		if (!grep(/^$rmqPath$/,@rmqPaths))
		{
			my $jsonObj = get_json_object_from_rmq($rmqHosts,$rmqPath);
			$jsonObj{$rmqPath} = map_rmq_elements($rmqPath,$jsonObj);
			push (@rmqPaths,$rmqPath);
		}
	}
	
	return \%jsonObj;
}

sub map_rmq_elements # func maps JSON data array to hash with unique id of elements in keys for different paths
{
	my ($apiPath,$jsonObj) = @_;
	my %elements;
	
	if ($apiPath eq "bindings") {
		%elements= map { $_->{'vhost'}.':'.$apiPath.':'.$_->{'destination'} => $_ } @$jsonObj;
	}
	elsif ($apiPath eq "nodes") {
		%elements = map { 'general:'.$apiPath.':'.$_->{'name'} => $_ } @$jsonObj;
	}
	elsif ($apiPath eq "federation-links") {
		%elements = map { $_->{'vhost'}.':'.$apiPath.':'.$_->{'exchange'} => $_ } @$jsonObj;
	}
	else {
		%elements = map { $_->{'vhost'}.':'.$apiPath.':'.$_->{'name'} => $_ } @$jsonObj;
	}
	
		return \%elements;
}

sub get_value_from_json # func goes recursively inside the JSON to get value
{
	my ($json,$path) = @_;
	my @pathSplit = split /\./,$path;
	my $element = shift @pathSplit;
	if (@pathSplit) {
		my $newPath = join('.',@pathSplit);
		return get_value_from_json($json->{$element},$newPath);
	}
	else {
		return $json->{$element};
	}
}

sub convert_to_epoch # func is used only for idle_since parameter, converts value to unixtime
{
	my $idleSince = shift;

	if ($idleSince) 
	{
		$idleSince =~ m/(\d+)-(\d+)-(\d+)\s(\d+):(\d+):(\d+)/;
		my ($year,$mon,$day,$hour,$min,$sec) = ($1-1900,$2-1,$3,$4,$5,$6);
		return my $unixtime = timelocal($sec,$min,$hour,$day,$mon,$year);
	}

	else { return 0; }
}
