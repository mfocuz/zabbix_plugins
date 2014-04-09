package ZabbixProxyDB;

# Package used for "Zabbix proxy/server scripts" <-> "Zabbix proxy/server DB" coloborations

use DBI;
use strict;

sub get_hosts_with_key {
        my $key = shift;
	my ( $db_name, $db_host, $db_user, $db_pass ) = @_;

        my $sql = 'SELECT DISTINCTROW h.host, interface.ip FROM hosts AS h, items AS i, interface as interface WHERE h.hostid=i.hostid and h.hostid=interface.hostid AND h.status=0 AND (i.status=0 or i.status=3) AND i.key_=\''.$key.'\'';
        $sql .= ';';

	my %servers = execute_query($sql,$db_name, $db_host, $db_user, $db_pass);

        return \%servers;
}

sub get_hosts_with_name_like {
	my $host = shift;
	my ( $db_name, $db_host, $db_user, $db_pass ) = @_;

	my $sql = 'select distinctrow h.host, interface.ip from hosts as h, interface as interface where h.host like \'%'.$host.'%\' and h.hostid=interface.hostid AND h.status=0';
	$sql .= ';';
	my %servers = execute_query($sql,$db_name, $db_host, $db_user, $db_pass);

	return \%servers;
}

sub get_items_for_host {
	my $host = shift;
	my ( $db_name, $db_host, $db_user, $db_pass ) = @_;
	
	my $sql = 'SELECT DISTINCTROW flags,key_ FROM items JOIN hosts ON hosts.hostid = items.hostid WHERE hosts.host="'.$host.'" and (items.flags=4 or items.flags=0);';
	my %items = execute_query($sql,$db_name, $db_host, $db_user, $db_pass);
	return \%items;
}

sub execute_query {
	my $sql = shift;
	my ( $db_name, $db_host, $db_user, $db_pass ) = @_;
	my %servers;
	my $dbh = DBI->connect('DBI:mysql:database='.$db_name.';host='.$db_host, $db_user, $db_pass, {'RaiseError' => 1});
	if (!defined $dbh) { print "Error: cannot connect to database.\n" && exit(1) };
	if (my $sth=$dbh->prepare($sql)) {
		if ($sth->execute()) {
			while (my @ret_arr = $sth->fetchrow_array) {
				$servers{$ret_arr[1]} = $ret_arr[0];
#                               print $ret_arr[0].' '.$ret_arr[1]."\n";
			}
		}
		else {
			print STDERR "Cannot execute query.\n";
			exit (1);
		}
	}

	else {
		print STDERR "Cannot prepare query\n";
		exit(1);
	}
	$dbh->disconnect();
	return %servers;
}

1;

