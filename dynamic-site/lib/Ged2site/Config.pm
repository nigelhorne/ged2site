package Ged2site::Config;

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

use warnings;
use strict;

use Carp;
use Config::Abstraction;
use CGI::Info;
use Data::Dumper;
use Error::Simple;
use File::Spec;
use Params::Get 0.13;

=encoding utf-8

=head1 NAME

Ged2site::Config - Site-independent configuration file for the Versatile Web Framework

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SUBROUTINES/METHODS

=head2 new

Creates a new Ged2site::Config instance with hierarchical configuration loading.

Takes four optional arguments:
	info (CGI::Info object)
	logger
	config_directory - used when the configuration directory can't be worked out
	config_file - name of the configuration file - otherwise determined dynamically
	config (ref to hash of values to override in the config file

Values in the file are overridden by what's in the environment

B<Parameters:>

=over 4

=item * C<info> - CGI::Info object (optional, created if not provided)

=item * C<logger> - Logger object with debug() method (optional)

=item * C<config_directory> - Additional config directory path (optional)

=item * C<config_file> - Specific config filename (optional)

=item * C<config> - Hash ref of override values (optional)

=back

B<Configuration Resolution Order:>
1. Base configuration files
2. Values from config parameter
3. Environment variable overrides

B<Directory Search Order:>
1. $ENV{CONFIG_DIR} (if set)
2. Provided config_directory
3. ../conf relative to script
4. ../../conf relative to script
5. $DOCUMENT_ROOT/../lib/conf
6. $HOME/lib/conf

B<Returns:> Blessed Ged2site::Config object

B<Throws:> Error::Simple on configuration errors

=head3 FORMAL SPECIFICATION

    [STRING, HASH, LOGGER]

    ConfigState ::= ⟨⟨ config_dirs : ℙ STRING;
                      config_data : HASH;
                      logger : LOGGER ⟩⟩

    ConfigArgs ::= ⟨⟨ info : CGI_Info;
                     logger : LOGGER;
                     config_directory : STRING;
                     config_file : STRING;
                     config : HASH ⟩⟩

    Init : ConfigArgs → ConfigState

    ∀ params : ConfigArgs •
      let dirs == if env.CONFIG_DIR ≠ ∅
                  then {env.CONFIG_DIR}
                  else default_dirs ∪ {params.config_directory} fi •
      let valid_dirs == {d : dirs | ∃ f : FILE • readable(d, f)} •
      valid_dirs ≠ ∅ ∧
      config_data ∈ HASH ∧
      config_data = merge(file_config, params.config, env_overrides)

    ValidConfigKey == {k : STRING | k ∈ dom config_data}

    GetConfigValue : ValidConfigKey → (STRING ∪ HASH ∪ ARRAY)

=cut

sub new
{
	my $proto = shift;
	my $params = Params::Get::get_params(undef, @_);

	if (exists $params->{logger} && defined $params->{logger}) {
		Throw Error::Simple('logger must be an object with debug method')
		    unless ref($params->{logger}) && $params->{logger}->can('debug');
	}

	if($params->{'logger'}) {
		$params->{'logger'}->debug(__PACKAGE__, '->new()');
	}

	if(exists $params->{config} && defined $params->{config}) {
		Throw Error::Simple('config must be a hash reference') unless ref($params->{config}) eq 'HASH';
	}

	my $class = ref($proto) || $proto;
	my $info = $params->{info} || CGI::Info->new();

	my @config_dirs;
	if($ENV{'CONFIG_DIR'}) {
		# Validate directory exists
		throw Error::Simple("CONFIG_DIR '$ENV{CONFIG_DIR}' does not exist or is not readable")
			unless -d $ENV{'CONFIG_DIR'} && -r $ENV{'CONFIG_DIR'};
		@config_dirs = ($ENV{'CONFIG_DIR'});
	} else {
		if($params->{config_directory}) {
			throw Error::Simple("config_directory must be a string") if(ref($params->{config_directory}));
			throw Error::Simple("config_directory '$params->{config_directory}' does not exist")
				unless -d $params->{config_directory};
			push(@config_dirs, $params->{config_directory});
		}
		@config_dirs = (
			File::Spec->catdir(
				$info->script_dir(),
				File::Spec->updir(),
				File::Spec->updir(),
				'conf'
			), File::Spec->catdir(
				$info->script_dir(),
				File::Spec->updir(),
				'conf'
			)
		);

		if($ENV{'DOCUMENT_ROOT'}) {
			push(@config_dirs, File::Spec->catdir(
				$ENV{'DOCUMENT_ROOT'},
				File::Spec->updir(),
				'lib',
				'conf'
			))
		}
		if($ENV{'HOME'}) {
			push(@config_dirs, File::Spec->catdir(
				$ENV{'HOME'},
				'lib',
				'conf'
			));
		}
	}

	# Look for localised configurations
	my $language;
	if(my $lingua = $params->{'lingua'}) {
		$language = $lingua->language_code_alpha2();
	}
	$language ||= $info->lang();

	if($language) {
		@config_dirs = map {
			($_, "$_/default", "$_/$language")
		} @config_dirs;
	} else {
		@config_dirs = map {
			($_, File::Spec->catdir($_, 'default'))
		} @config_dirs;
	}

	if($params->{'debug'}) {
		# Not sure this really does anything
		# $Config::Auto::Debug = 1;

		if($params->{logger}) {
			while(my ($key,$value) = each %ENV) {
				if($value) {
					$params->{logger}->debug("$key=$value");
				}
			}
		}
	}

	my $config;
	eval {
		$config = Config::Abstraction->new(
			config_dirs => \@config_dirs,
			config_files => ['default', $info->domain_name(), $ENV{'CONFIG_FILE'}, $params->{'config_file'}],
			logger => $params->{'logger'}
		)->all();
	};
	if($@ || !defined($config)) {
		throw Error::Simple("Configuration error: $@");
	}

	# Validate essential configuration structure
	throw Error::Simple('Configuration must be a hash reference') unless(ref($config) eq 'HASH');

	# The values in config are defaults which can be overridden by
	# the values in params->{config}
	if(defined($params->{'config'})) {
		$config = { %{$config}, %{$params->{'config'}} };
	}

	# Allow variables to be overridden by the environment
	foreach my $key(keys %{$config}) {
		if(my $value = $ENV{$key}) {
			# Validate environment variable names
			# throw Error::Simple("Invalid environment variable name: $key")
				# unless $key =~ /^[A-Z_][A-Z0-9_]*$/;

			# Sanitize values
			# $value =~ s/[^\w\s=\.\-]//g;	# Remove potentially dangerous characters

			if($params->{'logger'}) {
				$params->{'logger'}->debug(__PACKAGE__, ': ', __LINE__, " overwriting $key, ", $config->{$key}, " with $value");
			}
			# If the value contains an equals make it into a hash value
			if($value =~ /(.+)=(.+)/) {
				delete $config->{$key} if(!ref($config->{$key}));
				$config->{$key}{$1} = $2;
			} else {
				$config->{$key} = $value;
			}
		}
	}

	# Config::Any turns fields with spaces into arrays, put them back
	foreach my $field('Contents', 'SiteTitle') {
		my $value = $config->{$field};

		if(ref($value) eq 'ARRAY') {
			$config->{$field} = join(' ', @{$value});
		}
	}

	# unless($config->{'config_path'}) {
		# $config->{'config_path'} = File::Spec->catdir($config_dir, $info->domain_name());
	# }
	if($params->{'debug'} && $params->{'logger'}) {
		$params->{'logger'}->debug(__PACKAGE__, '(', __LINE__, '): ', Data::Dumper->new([$config])->Dump());
	}

	return bless $config, $class;
}

sub AUTOLOAD
{
	our $AUTOLOAD;
	my $self = shift;

	return undef unless($self);
	return unless defined($AUTOLOAD);

	# Extract the key name from the AUTOLOAD variable
	(my $key = $AUTOLOAD) =~ s/.*:://;

	return unless defined($key);

	# Don't handle special methods
	return if $key eq 'DESTROY';

	# Validate method name - only allow safe config keys
	Carp::croak(__PACKAGE__, ": Invalid key name: $key") unless $key =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/;

	# Return the value of the corresponding hash key
	# Only return existing keys to avoid auto-vivification
	return exists $self->{$key} ? $self->{$key} : undef;
}

1;
