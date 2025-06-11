package Ged2site::Display;

# Display a page. Certain variables are available to all templates, such as
# the stuff in the configuration file

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use strict;
use warnings;

use Config::Abstraction;
use CGI::Info;
use Data::Dumper;
use File::Spec;
use JSON::MaybeXS;
use Template::Filters;
use Template::Plugin::EnvHash;
use Template::Plugin::Math;
use Template::Plugin::JSON;
use HTML::SocialMedia;
use Ged2site::Utils;
use Error;
use Fatal qw(:void open);
use File::pfopen;
use Scalar::Util;

# TODO: read this from the config file
my %blacklist = (
	'MD' => 1,
	'RU' => 1,
	'CN' => 1,
	'BR' => 1,
	'UY' => 1,
	'TR' => 1,
	'MA' => 1,
	'VE' => 1,
	'SA' => 1,
	'CY' => 1,
	'CO' => 1,
	'MX' => 1,
	'IN' => 1,
	'RS' => 1,
	'PK' => 1,
);

our $sm;
our $smcache;

# Main display handler for generating web pages using Template Toolkit
# Handles security, throttling, localization, and template selection
sub new
{
	my $class = shift;

	# Handle hash or hashref arguments
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if(!defined($class)) {
		# Using Ged2site::Display->new(), not Ged2site::Display::new()
		# carp(__PACKAGE__, ' use ->new() not ::new() to instantiate');
		# return;

		# FIXME: this only works when no arguments are given
		$class = __PACKAGE__;
	} elsif(Scalar::Util::blessed($class)) {
		# If $class is an object, clone it with new arguments
		return bless { %{$class}, %args }, ref($class);
	}

	if(defined($ENV{'HTTP_REFERER'})) {
		# Protect against Shellshocker
		require Data::Validate::URI;
		Data::Validate::URI->import();

		unless(Data::Validate::URI->new()->is_uri($ENV{'HTTP_REFERER'})) {
			return;	# Block invalid referrers
		}
	}

	my $info = $args{info} || CGI::Info->new();

	unless($info->is_search_engine() || !defined($ENV{'REMOTE_ADDR'})) {
		# Intrusion Detection System integration
		require CGI::IDS;
		CGI::IDS->import();

		my $ids = CGI::IDS->new();
		$ids->set_scan_keys(scan_keys => 1);
		my $impact = $ids->detect_attacks(request => $info->params());
		if($impact > 0) {
			die "IDS impact is $impact";	# Block detected attacks
		}

		# Connection throttling system
		require Data::Throttler;
		Data::Throttler->import();

		# Handle YAML Errors
		my $db_file = File::Spec->catdir($info->tmpdir(), 'throttle');
		eval {
			my $throttler = Data::Throttler->new(
				max_items => 30,	# Allow 30 requests
				interval => 90,	# Per 90 second window
				backend => 'YAML',
				backend_options => {
					db_file => $db_file
				}
			);

			# Block if over the limit
			unless($throttler->try_push(key => $ENV{'REMOTE_ADDR'})) {
				$info->status(429);	# Too many requests
				sleep(1);	# Slow down attackers
				if($args{'logger'}) {
					$args{'logger'}->warn("$ENV{REMOTE_ADDR} connexion throttled");
				}
				return;
			}
		};
		if($@) {
			unlink($db_file);
		}

		# Country based blocking
		if(my $lingua = $args{lingua}) {
			if($blacklist{uc($lingua->country())}) {
				die "$ENV{REMOTE_ADDR} is from a blacklisted country ", $lingua->country();
			}
		}
	}

	# Configuration loading
	my $config_dir = _find_config_dir(\%args, $info);
	if($args{'logger'}) {
		$args{'logger'}->debug(__PACKAGE__, ' (', __LINE__, "): path = $config_dir");
	}
	my $config;
	eval {
		# Try default first, then domain-specific config first
		$config = Config::Abstraction->new(config_dirs => [$config_dir], config_files => ['default', $info->domain_name()])->all();
	};
	if($@ || !defined($config)) {
		die "Configuration error: $@: $config_dir/", $info->domain_name();
	}

	# The values in config are defaults which can be overridden by
	# the values in args{config}
	if(defined($args{'config'})) {
		$config = { %{$config}, %{$args{'config'}} };
	}

	# Initialise the template system
	Template::Filters->use_html_entities();

	# _ names included for legacy reasons, they will go away
	my $self = {
		_cachedir => $args{cachedir},
		config => $config,
		_config => $config,
		info => $info,
		_info => $info,
		_logger => $args{logger},
		%args,
	};

	if(my $lingua = $args{'lingua'}) {
		$self->{'lingua'} = $lingua;
		$self->{'_lingua'} = $lingua;
	}
	if(my $key = $info->param('key')) {
		$self->{'key'} = $key;
		$self->{'_key'} = $key;
	}
	if(my $page = $info->param('page')) {
		$self->{'page'} = $page;
		$self->{'_page'} = $page;
	}

	# Social media integration
	if(my $twitter = $config->{'twitter'}) {
		$smcache ||= create_memory_cache(config => $config, logger => $args{'logger'}, namespace => 'HTML::SocialMedia');
		$sm ||= HTML::SocialMedia->new({ twitter => $twitter, cache => $smcache, lingua => $args{lingua}, logger => $args{logger} });
		$self->{'_social_media'}->{'twitter_tweet_button'} = $sm->as_string(twitter_tweet_button => 1);
	} elsif(!defined($sm)) {
		$smcache = create_memory_cache(config => $config, logger => $args{'logger'}, namespace => 'HTML::SocialMedia');
		$sm = HTML::SocialMedia->new({ cache => $smcache, lingua => $args{lingua}, logger => $args{logger} });
	}
	$self->{'_social_media'}->{'facebook_share_button'} = $sm->as_string(facebook_share_button => 1);
	# $self->{'_social_media'}->{'google_plusone'} = $sm->as_string(google_plusone => 1);

	# Return the blessed object
	return bless $self, $class;
}

# Internal method to determine the configuration directory
sub _find_config_dir
{
	my($args, $info) = @_;

	if($ENV{'CONFIG_DIR'}) {
		return $ENV{'CONFIG_DIR'};
	}

	my $config_dir = File::Spec->catdir(
			$info->script_dir(),
			File::Spec->updir(),
			File::Spec->updir(),
			'conf'
		);

	if(!-d $config_dir) {
		$config_dir = File::Spec->catdir(
				$info->script_dir(),
				File::Spec->updir(),
				'conf'
			);
	}

	if(!-d $config_dir) {
		if($ENV{'DOCUMENT_ROOT'}) {
			$config_dir = File::Spec->catdir(
				# $ENV{'DOCUMENT_ROOT'},
				$info->rootdir(),
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
	}

	if(!-d $config_dir) {
		if($args->{config_directory}) {
			return $args->{config_directory};
		}
		if($args->{logger}) {
			while(my ($k, $v) = each %ENV) {
				$args->{logger}->debug("$k=$v");
			}
		}
	}

	return $config_dir;
}

# Call this to display the page
# It calls http() to create the HTTP headers, then html() to create the body
sub as_string {
	my ($self, $args) = @_;

	# TODO: Get all cookies and send them to the template.
	# 'cart' is an example
	unless($args && $args->{cart}) {
		if(my $purchases = $self->{_info}->get_cookie(cookie_name => 'cart')) {
			my %cart = split(/:/, $purchases);
			$args->{cart} = \%cart;
		}
	}

	# Calculate items in cart if not already present in $args
	unless($args && $args->{itemsincart}) {
		if($args->{cart}) {
			my $itemsincart;
			foreach my $key(keys %{$args->{cart}}) {
				if(defined($args->{cart}{$key}) && ($args->{cart}{$key} ne '')) {
					$itemsincart += $args->{cart}{$key};
				} else {
					delete $args->{cart}{$key};
				}
			}
			$args->{itemsincart} = $itemsincart;
		}
	}

	# my $html = $self->html($args);
	# unless($html) {
		# return;
	# }
	# return $self->http() . $html;

	# Build the HTTP response
	my $rc = $self->http();
	return $rc =~ /^Location:\s/ms ? $rc : $rc . $self->html($args);
}

# Determine the path to the correct template file based on various criteria such as language settings, browser type, and module path
sub get_template_path
{
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if($self->{_logger}) {
		$self->{_logger}->trace('Entering get_template_path');
	}

	if($self->{_filename}) {
		return $self->{_filename};
	}

	my $dir = $self->{_config}->{root_dir} || $self->{_info}->root_dir();
	if($self->{_logger}) {
		$self->{_logger}->debug(__PACKAGE__, ': ', __LINE__, ": root_dir $dir");
		$self->{_logger}->debug(Data::Dumper->new([$self->{_config}])->Dump());
	}
	$dir .= '/templates';

	my $prefix;

	# Look in .../robot or .../mobile first, if appropriate
	# Look in .../en/gb/web, then .../en/web then /web
	foreach my $browser_type($self->_types()) {
		if(my $lingua = $self->{_lingua}) {
			$self->_debug({ message => 'Requested language: ' . $lingua->requested_language() });
			# FIXME: look for lower priority languages if the highest isn't found
			if(my $language = $lingua->language_code_alpha2()) {
				if(my $dialect = $lingua->sublanguage_code_alpha2()) {
					$prefix .= "$dir/$browser_type/$language/$dialect:";
					$prefix .= "$dir/$browser_type/$language/default:";
				}
				$prefix .= "$dir/$language/$browser_type:" if(-d "$dir/$language/$browser_type");
				$prefix .= "$dir/$browser_type/$language:" if(-d "$dir/$browser_type/$language");
				$prefix .= "$dir/$browser_type/default:" if(-d "$dir/$browser_type/default");
				$prefix .= "$dir/default/$browser_type/:" if(-d "$dir/default/$browser_type");
			}
		}
		$prefix .= "$dir/$browser_type:" if(-d "$dir/$browser_type");
	}

	# Fall back to .../web, or if that fails, assume no web, robot or
	# mobile variant
	$prefix .= "$dir/web:$dir/default/web:$dir/default:$dir";

	$self->_debug({ message => "prefix: $prefix" });

	my $modulepath = $args{'modulepath'} || ref($self);
	$modulepath =~ s/::/\//g;

	if($prefix =~ /\.\.\//) {
		throw Error::Simple("Prefix must not contain ../ ($prefix)");
	}

	# Untaint the prefix value which may have been read in from a configuration file
	($prefix) = ($prefix =~ m/^([A-Z0-9_\.\-\/:]+)$/ig);

	my ($fh, $filename) = File::pfopen::pfopen($prefix, $modulepath, 'tmpl:tt:html:htm:txt');
	if((!defined($filename)) || (!defined($fh))) {
		throw Error::Simple("Can't find suitable $modulepath html or tmpl/tt file in $prefix in $dir or a subdir");
	}
	close($fh);
	$self->_debug({ message => "using $filename" });
	$self->{_filename} = $filename;

	# Remember the template filename
	if($self->{'log'}) {
		$self->{'log'}->template($filename);
	}

	return $filename;
}

=head2 set_cookie

Sets cookie values in the object.
Takes either a hash reference or a list of key-value pairs as input.
Iterates over the CGI parameters and stores them in the object's _cookies hash.
Returns the object itself, allowing for method chaining.

=cut

sub set_cookie
{
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	foreach my $key(keys(%params)) {
		$self->{_cookies}->{$key} = $params{$key};
	}
	return $self;
}

=head2 http

Returns the HTTP header section, terminated by an empty line

=cut

sub http
{
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Handle session cookies
	# TODO: Only session cookies as the moment
	if(my $cookies = $self->{_cookies}) {
		foreach my $cookie (keys(%{$cookies})) {
			my $value = exists $cookies->{$cookie} ? $cookies->{$cookie} : '0:0';
			print "Set-Cookie: $cookie=$value; path=/; HttpOnly\n";
		}
	}

	# Determine language, defaulting to English
	# TODO: Change the headers, e.g. character set, based on the language
	# my $language = $self->{_lingua} ? $self->{_lingua}->language() : 'English';

	my $rc;
	if($params{'Content-Type'}) {
		# Allow the content type to be forceably set
		$rc = $params{'Content-Type'} . "\n";
	} else {
		# Determine content type
		my $filename = $self->get_template_path();
		if ($filename =~ /\.txt$/) {
			$rc = "Content-Type: text/plain\n";
		} else {
			binmode(STDOUT, ':utf8');
			$rc = "Content-Type: text/html; charset=UTF-8\n";
		}
	}

	# Security headers
	# - Clickjacking protection
	# - MIME type enforcement
	# - Referrer policy
	# https://www.owasp.org/index.php/Clickjacking_Defense_Cheat_Sheet
	# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options

	# TODO: investigate Content-Security-Policy
	return $rc . "X-Frame-Options: SAMEORIGIN\n"
		. "X-Content-Type-Options: nosniff\n"
		. "Referrer-Policy: strict-origin-when-cross-origin\n\n";
}

# Run the given data through the template to create HTML

# Override this routine in a subclass if you wish to create special arguments to
# send to the template
sub html {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $filename = $self->get_template_path();
	my $rc;

	# Handle template files (.tmpl or .tt)
	if($filename =~ /.+\.t(mpl|t)$/) {
		require Template;
		Template->import();

		my $info = $self->{_info};

		# The values in config are defaults which can be overridden by
		# the values in info, then the values in params
		my $vals;
		if(defined($self->{_config})) {
			if($info->params()) {
				$vals = { %{$self->{_config}}, %{$info->params()} };
			} else {
				$vals = $self->{_config};
			}
			if(scalar(keys %params)) {
				$vals = { %{$vals}, %params };
			}
		} elsif(scalar(keys %params)) {
			$vals = { %{$info->params()}, %params };
		} else {
			$vals = $info->params();
		}
		$vals->{script_name} = $info->script_name();

		$vals->{cart} = $info->get_cookie(cookie_name => 'cart');
		$vals->{lingua} = $self->{_lingua};
		$vals->{social_media} = $self->{_social_media};
		$vals->{info} = $info;
		$vals->{as_string} = $info->as_string();

		my $template = Template->new({
			INTERPOLATE => 1,
			POST_CHOMP => 1,
			ABSOLUTE => 1,
			PLUGINS => { JSON => 'Template::Plugin::JSON' },
		});

		$self->_debug({ message => __PACKAGE__ . ': ' . __LINE__ . ': Passing these to the template: ' . join(', ', keys %{$vals}) });

		# Process the template
		if(!$template->process($filename, $vals, \$rc)) {
			if(my $err = $template->error()) {
				throw Error::Simple($err);
			}
			throw Error::Simple("Unknown error in template: $filename");
		}
	} elsif($filename =~ /\.(html?|txt)$/) {
		# Handle static HTML or text files
		open(my $fin, '<', $filename) || throw Error::Simple("$filename: $!");

		my @lines = <$fin>;

		close $fin;

		$rc = join('', @lines);
	} else {
		throw Error::Simple("Unhandled file type $filename");
	}

	# Check for mailto links and log a warning
	if(($filename !~ /.txt$/) && ($rc =~ /\smailto:(.+?)>/) && ($1 !~ /^&/) && $self->{_logger}) {
		$self->{_logger}->warn({ message => "Found mailto link $1, you should remove it or use " . obfuscate($1) . ' instead' });
	}

	return $rc;
}

sub _debug
{
	my $self = shift;

	if(my $logger = $self->{_logger}) {
		my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
		if(defined($ENV{'REMOTE_ADDR'})) {
			$logger->debug("$ENV{'REMOTE_ADDR'}: $params{'message'}");
		} else {
			$logger->debug($params{'message'});
		}
	}
	return $self;
}

sub obfuscate {
	return map { '&#' . ord($_) . ';' } split(//, shift);
}

sub _types
{
	my $self = shift;
	my $info = $self->{_info};
	my @rc;

	if($info->is_search_engine()) {
		push @rc, 'search', 'robot';
	} elsif($info->is_mobile()) {
		push @rc, 'mobile';
	} elsif($info->is_robot()) {
		push @rc, 'robot', 'search';
	}
	push @rc, 'web';

	return @rc;
}

1;
