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
use Config::Auto;
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

	my $config_dir;
	if($ENV{'CONFIG_DIR'}) {
		$config_dir = $ENV{'CONFIG_DIR'};
	} else {
		$config_dir = File::Spec->catdir(
				$info->script_dir(),
				File::Spec->updir(),
				File::Spec->updir(),
				'conf'
			);
		if($args{logger}) {
			$args{logger}->debug("Looking for configuration $config_dir/", $info->domain_name());
		}

		if(!-d $config_dir) {
			$config_dir = File::Spec->catdir(
					$info->script_dir(),
					File::Spec->updir(),
					'conf'
				);
			if($args{logger}) {
				$args{logger}->debug("Looking for configuration $config_dir/", $info->domain_name());
			}
		}

		if(!-d $config_dir) {
			if($ENV{'DOCUMENT_ROOT'}) {
				$config_dir = File::Spec->catdir(
					$ENV{'DOCUMENT_ROOT'},
					File::Spec->updir(),
					'lib',
					'conf'
				);
			} else {
				$config_dir = File::Spec->catdir(
					$ENV{'HOME'},
					'lib',
					'conf'
				);
			}
			if($args{logger}) {
				$args{logger}->debug("Looking for configuration $config_dir/", $info->domain_name());
			}
		}

		if(!-d $config_dir) {
			if($args{config_directory}) {
				$config_dir = $args{config_directory};
			} elsif($args{logger}) {
				while(my ($key,$value) = each %ENV) {
					$args{logger}->debug("$key=$value");
				}
			}
		}

		if(my $lingua = $args{'lingua'}) {
			my $language;
			if(($language = $lingua->language_code_alpha2()) && (-d "$config_dir/$language")) {
				$config_dir .= "/$language";
			} elsif(-d "$config_dir/default") {
				$config_dir .= '/default';
			}
		}
	}
	# if($args{'debug'}) {
		# # Not sure this really does anything
		# $Config::Auto::Debug = 1;
	# }
	my $config;
	my $config_file = $args{'config_file'} || $ENV{'CONFIG_FILE'} || File::Spec->catdir($config_dir, $info->domain_name());
	if($args{logger}) {
		$args{logger}->debug("Configuration path: $config_file");
	}
	eval {
		if(-r $config_file) {
			if($args{logger}) {
				$args{logger}->debug("Found configuration in $config_file");
			}
			$config = Config::Auto::parse($config_file);
		} elsif (-r File::Spec->catdir($config_dir, 'default')) {
			$config_file = File::Spec->catdir($config_dir, 'default');
			if($args{logger}) {
				$args{logger}->debug("Found configuration in $config_file");
			}
			$config = Config::Auto::parse('default', path => $config_dir);
		} else {
			die "no suitable config file found in $config_dir";
		}
	};
	if($@ || !defined($config)) {
		throw Error::Simple("$config_file: configuration error: $@");
	}

	# The values in config are defaults which can be overridden by
	# the values in args{config}
	if(defined($args{'config'})) {
		$config = { %{$config}, %{$args{'config'}} };
	}

	# Allow variables to be overridden by the environment
	foreach my $key(keys %{$config}) {
		if($ENV{$key}) {
			if($args{'logger'}) {
				$args{'logger'}->debug(__PACKAGE__, ': ', __LINE__, " overwriting $key, ", $config->{$key}, ' with ', $ENV{$key});
			}
			$config->{$key} = $ENV{$key};
		}
	}

	# Config::Any turns fields with spaces into arrays, put them back
	foreach my $field('Contents', 'SiteTitle') {
		my $value = $config->{$field};

		if(ref($value) eq 'ARRAY') {
			$config->{$field} = join(' ', @{$value});
		}
	}

	unless($config->{'config_path'}) {
		$config->{'config_path'} = File::Spec->catdir($config_dir, $info->domain_name());
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
