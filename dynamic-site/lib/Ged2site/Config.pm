package Ged2site::Config;

=head1 NAME

Ged2site::Config - Site-independent configuration file

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

# VWF is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

use warnings;
use strict;
use Config::Abstraction;
use CGI::Info;
use File::Spec;

=head1 SUBROUTINES/METHODS

=head2 new

Takes four optional arguments:
	info (CGI::Info object)
	logger
	config_directory - used when the configuration directory can't be worked out
	config_file - name of the configuration file - otherwise determined dynamically
	config (ref to hash of values to override in the config file

Values in the file are overridden by what's in the environment

=cut

sub new
{
	my $proto = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $class = ref($proto) || $proto;
	my $info = $args{info} || CGI::Info->new();

	if($args{'logger'}) {
		$args{'logger'}->debug(__PACKAGE__, '->new()');
	}

	my @config_dirs;
	if($ENV{'CONFIG_DIR'}) {
		@config_dirs = [$ENV{'CONFIG_DIR'}];
	} else {
		if($args{config_directory}) {
			push(@config_dirs, $args{config_directory});
		}
		push(@config_dirs, File::Spec->catdir(
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
	if(my $lingua = $args{'lingua'}) {
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

	if($args{'debug'}) {
		# Not sure this really does anything
		# $Config::Auto::Debug = 1;

		if($args{logger}) {
			while(my ($key,$value) = each %ENV) {
				if($value) {
					$args{logger}->debug("$key=$value");
				}
			}
		}
	}

	my $config = Config::Abstraction->new(
		config_dirs => \@config_dirs,
		config_files => ['default', $info->domain_name(), $ENV{'CONFIG_FILE'}, $args{'config_file'}],
		logger => $args{'logger'})->all();
	if($@ || !defined($config)) {
		throw Error::Simple("Configuration error: $@");
	}

	# The values in config are defaults which can be overridden by
	# the values in args{config}
	if(defined($args{'config'})) {
		$config = { %{$config}, %{$args{'config'}} };
	}

	# Allow variables to be overridden by the environment
	foreach my $key(keys %{$config}) {
		if(my $value = $ENV{$key}) {
			if($args{'logger'}) {
				$args{'logger'}->debug(__PACKAGE__, ': ', __LINE__, " overwriting $key, ", $config->{$key}, " with $value");
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
	if($args{'debug'} && $args{'logger'}) {
		$args{'logger'}->debug(__PACKAGE__, '(', __LINE__, '): ', Data::Dumper->new([$config])->Dump());
	}

	return bless $config, $class;
}

sub AUTOLOAD
{
	our $AUTOLOAD;
	my $self = shift;

	return undef unless($self);

	# Extract the method name from the AUTOLOAD variable
	(my $key = $AUTOLOAD) =~ s/.*:://;

	# Return the value of the corresponding hash key
	return $self->{$key};
}

1;
