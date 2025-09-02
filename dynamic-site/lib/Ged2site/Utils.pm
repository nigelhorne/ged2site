package Ged2site::Utils;

# VWF is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

=head1 NAME

Ged2site::Utils - Random subroutines for Ged2site

=head1 DESCRIPTION

Utility module for cache management and geospatial calculations.
Provides cross-driver cache initialization and Haversine formula implementation.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(create_disc_cache create_memory_cache distance);

use CHI;
use Data::Dumper;
use DBI;
use Error;
use Log::Any::Adapter;
use Params::Get;

BEGIN {
	Log::Any::Adapter->set('Log4perl');
}

=head1 SUBROUTINES/METHODS

=head2 create_disc_cache

Initialise a disc-based cache using the CHI module.
Supports multiple cache drivers, including BerkeleyDB, DBI, and Redis.

=cut

sub create_disc_cache {
	my $args = Params::Get::get_params(undef, @_);

	my $config = $args->{'config'};
	throw Error::Simple('config is not optional') unless($config);

	my $logger = $args->{'logger'};
	my $driver = $config->{disc_cache}->{driver};

	# Default to BerkeleyDB if no driver specified
	unless(defined($driver)) {
		my $root_dir = $ENV{'root_dir'} || $args->{'root_dir'} || $config->{disc_cache}->{root_dir} || $config->{'root_dir'};
		throw Error::Simple($config->{'config_path'} . ': root_dir is not optional') unless($root_dir);

		if($logger) {
			$logger->debug(Data::Dumper->new([$config])->Dump());
			$logger->info('disc_cache not defined in ', $config->{'config_path'}, ' falling back to BerkeleyDB');
		}
		return CHI->new(driver => 'BerkeleyDB', root_dir => $root_dir, namespace => $args->{'namespace'});
	}
	if($logger) {
		$logger->debug('disc cache via ', $config->{disc_cache}->{driver}, ', namespace: ', $args->{'namespace'});
	}

	my %chi_args = (
		on_get_error => 'warn',
		on_set_error => 'die',
		driver => $driver,
		namespace => $args->{'namespace'}
	);

	# Don't do this because it takes a lot of complex configuration
	# if($logger) {
		# $chi_args{'on_set_error'} = 'log';
		# $chi_args{'on_get_error'} = 'log';
	# }

	if($config->{disc_cache}->{server}) {
		my @servers;
		if($config->{disc_cache}->{server} =~ /,/) {
			@servers = split /,/, $config->{disc_cache}->{server};
		} else {
			$servers[0] = $config->{disc_cache}->{server};
			if($config->{disc_cache}->{'port'}) {
				$servers[0] .= ':' . $config->{disc_cache}->{port};
			} else {
				throw Error::Simple('port is not optional in ' . $config->{'config_path'});
			}
			$chi_args{'server'} = $servers[0];
			if($logger) {
				$logger->debug("First server: $servers[0]");
			}
		}
		$chi_args{'servers'} = \@servers;
	} elsif($driver eq 'DBI') {
		# Use the cache connection details in the configuration file
		$chi_args{'dbh'} = DBI->connect($config->{disc_cache}->{connect});
		if(!defined($chi_args{'dbh'})) {
			if($logger) {
				$logger->error($DBI::errstr);
			}
			throw Error::Simple($DBI::errstr);
		}
		$chi_args{'create_table'} = 1;
	} elsif($driver eq 'Redis') {
		my %redis_options = (
			reconnect => 60,
			every => 1_000_000
		);
		$chi_args{'redis_options'} = \%redis_options;
	} elsif($driver ne 'Null') {
		$chi_args{'root_dir'} = $ENV{'root_dir'} || $args->{'root_dir'} || $config->{disc_cache}->{root_dir};
		throw Error::Simple('root_dir is not optional') unless($chi_args{'root_dir'});
		if($logger) {
			$logger->debug("root_dir: $chi_args{root_dir}");
		}
	}
	return CHI->new(%chi_args);
}

=head2 create_memory_cache

Initialise a memory-based cache using the CHI module.
Supports multiple cache drivers, including SharedMem, Memory, and Redis.

=cut

sub create_memory_cache {
	my $args = Params::Get::get_params(undef, @_);

	my $config = $args->{'config'};
	throw Error::Simple('config is not optional') unless($config);

	my $logger = $args->{'logger'};
	my $driver = $config->{'memory_cache'}->{driver};
	unless(defined($driver)) {
		if($logger) {
			$logger->debug(Data::Dumper->new([$config])->Dump());
			$logger->info('memory_cache not defined in ', $config->{'config_path'}, ' falling back to memory');
		}
		# return CHI->new(driver => 'Memcached', servers => [ '127.0.0.1:11211' ], namespace => $args->{'namespace'});
		# return CHI->new(driver => 'File', root_dir => '/tmp/cache', namespace => $args->{'namespace'});
		# return CHI->new(driver => 'SharedMem', max_size => 1024, shm_size => 16 * 1024, shm_key => 98766789, namespace => $args->{'namespace'});
		return CHI->new(driver => 'Memory', global => 1);
	}
	if($logger) {
		$logger->debug('memory cache via ', $config->{memory_cache}->{driver}, ', namespace: ', $args->{'namespace'});
	}

	my %chi_args = (
		on_get_error => 'warn',
		on_set_error => 'die',
		driver => $driver,
		namespace => $args->{'namespace'}
	);

	if($logger) {
		$chi_args{'on_set_error'} = 'log';
		$chi_args{'on_get_error'} = 'log';
	}

	if($config->{memory_cache}->{server}) {
		my @servers;
		if($config->{memory_cache}->{server} =~ /,/) {
			@servers = split /,/, $config->{memory_cache}->{server};
		} else {
			$servers[0] = $config->{memory_cache}->{server};
			if($config->{memory_cache}->{'port'}) {
				$servers[0] .= ':' . $config->{memory_cache}->{port};
			} else {
				throw Error::Simple('port is not optional in ' . $config->{'config_path'});
			}
			$chi_args{'server'} = $servers[0];
			if($logger) {
				$logger->debug("First server: $servers[0]");
			}
		}
		$chi_args{'servers'} = \@servers;
	} elsif($driver eq 'SharedMem') {
		$chi_args{'shm_key'} = $args->{'shm_key'} || $config->{memory_cache}->{shm_key};
		if(my $shm_size = ($args->{'shm_size'} || $config->{'memory_cache'}->{'shm_size'})) {
			$chi_args{'shm_size'} = $shm_size;
		}
		if(my $max_size = ($args->{'max_size'} || $config->{'memory_cache'}->{'max_size'})) {
			$chi_args{'max_size'} = $max_size;
		}
	} elsif($driver eq 'Memory') {
		$chi_args{'global'} = exists($config->{'memory_cache'}->{'global'}) ? $config->{'memory_cache'}->{'global'} : 0;
		if($chi_args{'global'} == 0) {
                        $chi_args{'datastore'} = {};
                }
	} elsif($driver ne 'Null') {
		$chi_args{'root_dir'} = $ENV{'root_dir'} || $args->{'root_dir'} || $config->{memory_cache}->{root_dir} || $config->{'root_dir'};
		throw Error::Simple('root_dir is not optional') unless($chi_args{'root_dir'});
		if($logger) {
			$logger->debug("root_dir: $chi_args{root_dir}");
		}
	} elsif($driver eq 'Redis') {
		my %redis_options = (
			reconnect => 60,
			every => 1_000_000
		);
		$chi_args{'redis_options'} = \%redis_options;
	}
	return CHI->new(%chi_args);
}

=head2 distance

Calculate the distance between two geographical points using latitude and longitude.
Supports distance in kilometres (K), nautical miles (N), or miles.

From L<http://www.geodatasource.com/developers/perl>
FIXME: use Math::Trig

=cut

sub distance {
	my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
	my $theta = $lon1 - $lon2;
	my $dist = sin(_deg2rad($lat1)) * sin(_deg2rad($lat2)) + cos(_deg2rad($lat1)) * cos(_deg2rad($lat2)) * cos(_deg2rad($theta));
	$dist = _acos($dist);
	$dist = _rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
	if ($unit eq 'K') {
		$dist = $dist * 1.609344;	# number of kilometres in a mile
	} elsif ($unit eq 'N') {
		$dist = $dist * 0.8684;
	}
	return ($dist);
}

my $pi = atan2(1,1) * 4;

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function get the arccos function using arctan function   :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _acos {
	my $rad = shift;
	my $ret = atan2(sqrt(1 - $rad**2), $rad);
	return $ret;
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts decimal degrees to radians             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _deg2rad {
	my $deg = shift;
	return ($deg * $pi / 180);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts radians to decimal degrees             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub _rad2deg {
	my $rad = shift;
	return ($rad * 180 / $pi);
}

1;
