#!/usr/bin/perl

use JMXDiscovery;
use JSON::XS;
use strict;

my $conn = $ARGV[0];
my $port = $ARGV[1];
my $regexp = $ARGV[2];

my $mbeans;
my $values;

# Example of regexp, not sure why we add () but it required by java regexps...
# my $regexp = "(.*type=ConnectionManager.*)"; # example of regexp

# JavaGateway server address:port
my $JMXLLDserver = "127.0.0.1:10052";

my $jmxd = JMXDiscovery->new($JMXLLDserver, $conn, $port);
my $json = JSON::XS->new->utf8;

my $response = $jmxd->get_mbeans($regexp);
$response = decode_json($response);
$mbeans = $response->{data};

my $data;
my $name;

foreach my $bean (@$mbeans) {   
    my $beanForZBX = {        
        '{#MBEAN}' => $bean,
        '{#BEANNAME}' => $name,
    };
    push @$data, $beanForZBX;
}

my $discoveryData = {
    data => $data,
};

print $json->pretty->encode($discoveryData);

