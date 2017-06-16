package main;

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

use strict;
use warnings;
use CHI;
use Error;
use POSIX;

my $pi = atan2(1,1) * 4;

sub create_disc_cache {
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $config = $args{'config'};
	throw Error::Simple('config is not optional') unless($config);

	my $logger = $args{'logger'};
	my $driver = $config->{disc_cache}->{driver};
	unless(defined($driver)) {
		my $root_dir = $args{'root_dir'} || $config->{disc_cache}->{root_dir};
		throw Error::Simple('root_dir is not optional') unless($root_dir);

		if($logger) {
			$logger->warn('disc_cache not defined in ' . $config->{'config_path'} . ' falling back to BerkeleyDB');
		}
		return CHI->new(driver => 'BerkeleyDB', root_dir => $root_dir, namespace => $args{'namespace'});
	}
	if($logger) {
		$logger->debug('disc cache via ', $config->{disc_cache}->{driver}, ', namespace: ', $args{'namespace'});
	}

	my %chi_args = (
		on_get_error => 'warn',
		on_set_error => 'die',
		driver => $driver,
		namespace => $args{'namespace'}
	);

	if($config->{disc_cache}->{server}) {
		my @servers;
		if($config->{disc_cache}->{server} =~ /,/) {
			@servers = split /,/, $config->{disc_cache}->{server};
		} else {
			$servers[0] = $config->{disc_cache}->{server};
			if($config->{disc_cache}->{'port'}) {
				$servers[0] .= ':' . $config->{disc_cache}->{port};
			} else {
				throw Error::Simple('port is not optional');
			}
			$chi_args{'server'} = $servers[0];
			if($logger) {
				$logger->debug("First server: $servers[0]");
			}
		}
		$chi_args{'servers'} = \@servers;
	} elsif(($driver ne 'DBI') && ($driver ne 'Null')) {
		$chi_args{'root_dir'} = $args{'root_dir'} || $config->{disc_cache}->{root_dir};
		throw Error::Simple('root_dir is not optional') unless($chi_args{'root_dir'});
		if($logger) {
			$logger->debug("root_dir: $chi_args{root_dir}");
		}
	}
	if($driver eq 'Redis') {
		my %redis_options = (
			reconnect => 60,
			every => 1_000_000
		);
		$chi_args{'redis_options'} = \%redis_options;
	} elsif($driver eq 'DBI') {
		$chi_args{'dbh'} = DBI->connect($config->{disc_cache}->{connect});
		$chi_args{'create_table'} = 1;
	}
	return CHI->new(%chi_args);
}

sub create_memory_cache {
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $config = $args{'config'};
	throw Error::Simple('config is not optional') unless($config);

	my $logger = $args{'logger'};
	my $driver = $config->{memory_cache}->{driver};
	unless(defined($driver)) {
		# FIXME: not everywhere runs memcache, should fall back to something else
		if($logger) {
			$logger->warn('memory_cache not defined in ' . $config->{'config_path'} . ' falling back to memcached');
		}
		return CHI->new(driver => 'Memcached', servers => [ '127.0.0.1:11211' ], namespace => $args{'namespace'});
	}
	if($logger) {
		$logger->debug('memory cache via ', $config->{memory_cache}->{driver}, ', namespace: ', $args{'namespace'});
	}

	my %chi_args = (
		on_get_error => 'warn',
		on_set_error => 'die',
		driver => $driver,
		namespace => $args{'namespace'}
	);

	if($config->{memory_cache}->{server}) {
		my @servers;
		if($config->{memory_cache}->{server} =~ /,/) {
			@servers = split /,/, $config->{memory_cache}->{server};
		} else {
			$servers[0] = $config->{memory_cache}->{server};
			if($config->{memory_cache}->{'port'}) {
				$servers[0] .= ':' . $config->{memory_cache}->{port};
			} else {
				throw Error::Simple('port is not optional');
			}
			$chi_args{'server'} = $servers[0];
			if($logger) {
				$logger->debug("First server: $servers[0]");
			}
		}
		$chi_args{'servers'} = \@servers;
	} elsif($driver ne 'Null') {
		$chi_args{'root_dir'} = $args{'root_dir'} || $config->{memory_cache}->{root_dir};
		throw Error::Simple('root_dir is not optional') unless($chi_args{'root_dir'});
		if($logger) {
			$logger->debug("root_dir: $chi_args{root_dir}");
		}
	}
	if($driver eq 'Redis') {
		my %redis_options = (
			reconnect => 60,
			every => 1_000_000
		);
		$chi_args{'redis_options'} = \%redis_options;
	}
	return CHI->new(%chi_args);
}

# From http://www.geodatasource.com/developers/perl
# FIXME:  use Math::Trig
sub distance {
	my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
	my $theta = $lon1 - $lon2;
	my $dist = sin(_deg2rad($lat1)) * sin(_deg2rad($lat2)) + cos(_deg2rad($lat1)) * cos(_deg2rad($lat2)) * cos(_deg2rad($theta));
	$dist = _acos($dist);
	$dist = _rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
	if ($unit eq "K") {
		$dist = $dist * 1.609344;
	} elsif ($unit eq "N") {
		$dist = $dist * 0.8684;
	}
	return ($dist);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function get the arccos function using arctan function   :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _acos {
	my ($rad) = @_;
	my $ret = atan2(sqrt(1 - $rad**2), $rad);
	return $ret;
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts decimal degrees to radians             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _deg2rad {
	my ($deg) = @_;
	return ($deg * $pi / 180);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts radians to decimal degrees             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _rad2deg {
	my ($rad) = @_;
	return ($rad * 180 / $pi);
}

1;
