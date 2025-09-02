package Ged2site::Utils;

# Ged2site is licensed under GPL2.0 for personal use only
# njh@nigelhorne.com

=encoding utf-8

=head1 NAME

Ged2site::Utils - Random subroutines for Ged2site

=head1 DESCRIPTION

Utility module for cache management and geospatial calculations.
Provides cross-driver cache initialization and Haversine formula implementation.

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

use v5.20;
use strict;
use warnings;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use Exporter qw(import);
our @EXPORT = qw(create_disc_cache create_memory_cache distance);

use CHI;
use Data::Dumper;
use DBI;
use Error::Simple;
use Params::Get 0.13;
use Try::Tiny;
use Carp qw(croak carp);
use Scalar::Util qw(looks_like_number);
use Math::Trig qw(deg2rad rad2deg acos great_circle_distance);

# Constants for distance calculations
use constant {
	EARTH_RADIUS_MILES => 3959,
	EARTH_RADIUS_KM => 6371,
	EARTH_RADIUS_NM => 3440,
	KM_PER_MILE => 1.609344,
	NM_PER_MILE => 0.8684
};

=head1 SUBROUTINES/METHODS

=head2 FORMAL SPECIFICATION

	[STRING, HASH, LOGGER, CHI_CACHE, COORDINATE]

	CacheConfig ::= ⟨⟨ driver : STRING;
					 servers : seq STRING;
					 root_dir : STRING;
					 connect : STRING ⟩⟩

	CacheArgs ::= ⟨⟨ config : HASH;
					logger : LOGGER;
					namespace : STRING;
					root_dir : STRING ⟩⟩

	Point ::= ⟨⟨ latitude : COORDINATE;
				longitude : COORDINATE ⟩⟩
	where
	  latitude ∈ {x : ℝ | -90 ≤ x ≤ 90} ∧
	  longitude ∈ {x : ℝ | -180 ≤ x ≤ 180}

	Unit ::= K | N | M

	CreateCache : CacheArgs → CHI_CACHE

	∀ args : CacheArgs •
	  let driver == args.config.driver ∨ default_driver •
	  validate_driver_config(driver, args.config) ∧
	  ∃ cache : CHI_CACHE • cache = CHI.new(build_chi_args(driver, args))

	Distance : Point × Point × Unit → ℝ₊

	∀ p1, p2 : Point; u : Unit •
	  let d == great_circle_distance(p1, p2) •
	  d ≥ 0 ∧
	  (u = K ⟹ result = d × 1.609344) ∧
	  (u = N ⟹ result = d × 0.8684) ∧
	  (u = M ⟹ result = d)

=head2 create_disc_cache

Initialize a disc-based cache using the CHI module.
Supports multiple cache drivers, including BerkeleyDB, DBI, and Redis.

Parameters:
- config: Configuration hash reference (required)
- logger: Logger object (optional)
- namespace: Cache namespace (optional)
- root_dir: Root directory override (optional)

Returns: CHI cache object

=cut

sub create_disc_cache {
	my $args = Params::Get::get_params(undef, @_);
	return _create_cache('disc_cache', $args);
}

=head2 create_memory_cache

Initialize a memory-based cache using the CHI module.
Supports multiple cache drivers, including SharedMem, Memory, and Redis.

Parameters:
- config: Configuration hash reference (required)
- logger: Logger object (optional)
- namespace: Cache namespace (optional)
- root_dir: Root directory override (optional)

Returns: CHI cache object

=cut

sub create_memory_cache {
	my $args = Params::Get::get_params(undef, @_);
	return _create_cache('memory_cache', $args);
}

# Private helper functions

sub _create_cache($cache_type, $args) {
	my $config = $args->{'config'};
	throw Error::Simple('config is not optional') unless($config);

	_validate_cache_config($config, $cache_type);

	my $logger = $args->{'logger'};
	my $cache_config = $config->{$cache_type} || {};
	my $driver = $cache_config->{driver};

	# Set default driver with fallback strategy
	unless (defined $driver) {
		$driver = _get_default_driver($cache_type, $logger);
		if ($logger) {
			$logger->info("No driver specified for $cache_type, using $driver");
		}
	}

	# Validate driver is available
	unless (_is_driver_available($driver)) {
		my $fallback = _get_fallback_driver($cache_type);
		if ($logger) {
			$logger->warn("Driver $driver not available, falling back to $fallback");
		}
		$driver = $fallback;
	}

	# Build CHI arguments
	my %chi_args = _build_chi_args($driver, $cache_config, $args, $logger, $cache_type);

	# Create cache with error handling
	my $cache;
	try {
		$cache = CHI->new(%chi_args);
	} catch {
		my $error = "Failed to create $cache_type cache with driver $driver: $_";
		$logger->error($error) if $logger;
		throw Error::Simple($error);
	};

	return $cache;
}

sub _validate_cache_config($config, $cache_type) {
	return unless exists $config->{$cache_type};

	my $cache_config = $config->{$cache_type};
	croak('Cache configuration must be a hash reference')
		unless ref($cache_config) eq 'HASH';

	# Validate driver if specified
	if (exists $cache_config->{driver}) {
		my $driver = $cache_config->{driver};
		my @valid_drivers = qw(Memory BerkeleyDB DBI Redis Memcached SharedMem File Null);
		croak "Invalid driver '$driver'. Valid drivers: " . join(', ', @valid_drivers)
			unless grep { $_ eq $driver } @valid_drivers;
	}

	# Validate numeric parameters
	for my $param (qw(port shm_size max_size)) {
		next unless exists $cache_config->{$param};
		my $value = $cache_config->{$param};
		croak "$param must be a positive integer"
			unless defined $value && $value =~ /^\d+$/ && $value > 0;
	}

	# Validate port range
	if (exists $cache_config->{port}) {
		my $port = $cache_config->{port};
		croak('Port must be between 1 and 65535')
			unless $port >= 1 && $port <= 65535;
	}
}

sub _get_default_driver($cache_type, $logger) {
	# Allow override for testing
	my $env_var = 'TEST_' . uc($cache_type) . '_DRIVER';
	return $ENV{$env_var} if $ENV{$env_var};

	# Production defaults
	return $cache_type eq 'disc_cache' ? 'BerkeleyDB' : 'Memory';
}

sub _get_fallback_driver($cache_type) {
	return $cache_type eq 'disc_cache' ? 'File' : 'Memory';
}

sub _is_driver_available($driver) {
	return 1 if $driver =~ /^(Memory|Null)$/;

	my %driver_modules = (
		'Redis' => 'CHI::Driver::Redis',
		'DBI' => 'CHI::Driver::DBI',
		'BerkeleyDB' => 'CHI::Driver::BerkeleyDB',
		'Memcached' => 'CHI::Driver::Memcached',
		'SharedMem' => 'CHI::Driver::SharedMem',
		'File' => 'CHI::Driver::File'
	);

	return 1 unless exists $driver_modules{$driver};

	eval "require $driver_modules{$driver}";
	return !$@;
}

sub _build_chi_args($driver, $cache_config, $args, $logger, $cache_type) {
	my %chi_args = (
		driver => $driver,
		namespace => $args->{'namespace'} || 'default'
	);

	# Configure error handling
	if ($logger && $logger->can('error')) {
		$chi_args{on_get_error} = sub { $logger->warn("Cache get error: $_[0]") };
		$chi_args{on_set_error} = sub { $logger->error("Cache set error: $_[0]") };
	} else {
		$chi_args{on_get_error} = 'warn';
		$chi_args{on_set_error} = 'die';
	}

	# Driver-specific configuration
	if ($driver eq 'Redis') {
		_configure_redis(\%chi_args, $cache_config, $args, $logger);
	} elsif ($driver eq 'DBI') {
		_configure_dbi(\%chi_args, $cache_config, $args, $logger);
	} elsif ($driver eq 'SharedMem') {
		_configure_shared_memory(\%chi_args, $cache_config, $args);
	} elsif ($driver eq 'Memory') {
		_configure_memory(\%chi_args, $cache_config);
	} elsif ($driver eq 'Memcached') {
		_configure_memcached(\%chi_args, $cache_config, $args, $logger);
	} elsif ($driver !~ /^(Null)$/) {
		_configure_file_based(\%chi_args, $cache_config, $args);
	}

	return %chi_args;
}

sub _configure_redis($chi_args, $config, $args, $logger) {
	# Parse server configuration
	my @servers = _parse_server_config($config, $logger);
	if (@servers) {
		$chi_args->{servers} = \@servers;
		$chi_args->{server} = $servers[0];	# Primary server
	}

	# Redis-specific options with sensible defaults
	$chi_args->{redis_options} = {
		reconnect => $config->{reconnect} || 60,
		every => $config->{every} || 1_000_000,
		encoding => $config->{encoding} || 'utf8',
		%{$config->{redis_options} || {}}
	};
}

sub _configure_dbi($chi_args, $config, $args, $logger) {
	my $connect_string = $config->{connect};
	croak "DBI driver requires 'connect' parameter" unless $connect_string;

	my $dbh;
	try {
		$dbh = DBI->connect($connect_string, '', '', {
			RaiseError => 1,
			PrintError => 0,
			AutoCommit => 1
		});
	} catch {
		my $error = "Failed to connect to database: $_";
		$logger->error($error) if $logger;
		croak $error;
	};

	$chi_args->{dbh} = $dbh;
	$chi_args->{create_table} = $config->{create_table} // 1;
}

sub _configure_shared_memory($chi_args, $config, $args) {
	$chi_args->{shm_key} = $args->{'shm_key'} || $config->{shm_key}
		|| croak "SharedMem driver requires 'shm_key' parameter";

	$chi_args->{shm_size} = $args->{'shm_size'} || $config->{shm_size} || 16 * 1024;
	$chi_args->{max_size} = $args->{'max_size'} || $config->{max_size} || 1024;
}

sub _configure_memory($chi_args, $config) {
	$chi_args->{'global'} = $config->{'global'} // 1;
	if(!$chi_args->{'global'}) {
		$chi_args->{'datastore'} = {};
	}
}

sub _configure_memcached($chi_args, $config, $args, $logger) {
	my @servers = _parse_server_config($config, $logger);
	if (@servers) {
		$chi_args->{servers} = \@servers;
	} else {
		# Default to localhost
		$chi_args->{servers} = ['127.0.0.1:11211'];
		$logger->debug('Using default Memcached server: 127.0.0.1:11211') if $logger;
	}
}

sub _configure_file_based($chi_args, $config, $args) {
	my $root_dir = $ENV{'root_dir'} || $args->{'root_dir'} ||
				 $config->{root_dir} || $args->{'config'}->{root_dir};

	croak "File-based cache drivers require 'root_dir' parameter" unless $root_dir;
	croak "Root directory '$root_dir' does not exist or is not writable"
		unless -d $root_dir && -w $root_dir;

	$chi_args->{root_dir} = $root_dir;
}

sub _parse_server_config($config, $logger) {
	# Handle host/server naming inconsistency
	my $server_config = $config->{server} || $config->{host};
	return () unless $server_config;

	my @servers;
	for my $server_entry (split /,/, $server_config) {
		$server_entry =~ s/^\s+|\s+$//g;	# trim whitespace

		# If no port specified, add default port
		unless ($server_entry =~ /:/) {
			my $port = $config->{port} || croak "Port not specified for server '$server_entry'";
			$server_entry .= ":$port";
		}

		# Validate server format
		if ($server_entry =~ /^([a-zA-Z0-9.-]+):(\d+)$/) {
			my ($host, $port) = ($1, $2);
			croak "Invalid port number: $port" unless $port > 0 && $port <= 65535;
			push @servers, $server_entry;
			$logger->debug("Added server: $server_entry") if $logger;
		} else {
			croak "Invalid server format: '$server_entry' (expected host:port)";
		}
	}

	return @servers;
}

=head2 distance

Calculate the great circle distance between two points on Earth using the Haversine formula.
More accurate than the original implementation, especially for short distances.

Parameters:
- lat1, lon1: Latitude and longitude of first point (decimal degrees)
- lat2, lon2: Latitude and longitude of second point (decimal degrees)
- unit: 'K' for kilometers, 'N' for nautical miles, 'M' or undef for statute miles

Returns: Distance in specified units

Throws: Error on invalid input parameters

=cut

sub distance($lat1, $lon1, $lat2, $lon2, $unit = 'M') {
	# Input validation
	for my $coord_ref ([\$lat1, 'lat1'], [\$lon1, 'lon1'], [\$lat2, 'lat2'], [\$lon2, 'lon2']) {
		my ($coord, $name) = @$coord_ref;
		croak "$name must be defined" unless defined $$coord;
		croak "$name must be numeric" unless looks_like_number($$coord);
	}

	# Range validation
	croak('Latitude must be between -90 and 90 degrees')
		if abs($lat1) > 90 || abs($lat2) > 90;
	croak('Longitude must be between -180 and 180 degrees')
		if abs($lon1) > 180 || abs($lon2) > 180;

	# Handle identical points
	return 0 if $lat1 == $lat2 && $lon1 == $lon2;

	# Validate unit
	$unit = uc($unit || 'M');
	croak "Unknown unit '$unit'. Use 'K', 'N', or 'M'"
		unless $unit =~ /^[KNM]$/;

	# Use optimized calculation with appropriate radius
	my $radius = $unit eq 'K' ? EARTH_RADIUS_KM :
				 $unit eq 'N' ? EARTH_RADIUS_NM :
				 EARTH_RADIUS_MILES;

	# Haversine formula
	my $dlat = deg2rad($lat2 - $lat1);
	my $dlon = deg2rad($lon2 - $lon1);
	my $a = sin($dlat/2)**2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dlon/2)**2;
	my $c = 2 * asin(sqrt($a));

	return $radius * $c;
}

1;

__END__

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Ged2site::Utils

=head1 LICENSE AND COPYRIGHT

Ged2site is licensed under GPL2.0 for personal use only.
Commercial users must apply in writing for a licence.

=head1 SEE ALSO

L<CHI>, L<Math::Trig>, L<DBI>

=cut
