#!/usr/bin/env perl

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# Can be tested at the command line, e.g.:
#	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi page=index
# To mimic a French mobile site:
#	root_dir=$(pwd)/.. ./page.fcgi --mobile page=index lang=fr
# To turn off the linting of HTML on a search-engine landing page
#	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi --search-engine page=index lint_content=0

use strict;
use warnings;
# use diagnostics;

BEGIN {
	# Sanitize environment variables
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
	$ENV{'PATH'} = '/usr/local/bin:/bin:/usr/bin';	# For insecurity
}

no lib '.';

use Log::WarnDie 0.09;
use Carp::Always;
use CGI::ACL 0.06;	# For deny_cloud
use CGI::Carp qw(fatalsToBrowser);
use CGI::Info 0.94;	# Gets all messages
use CGI::Lingua 0.61;
use CHI;
use Class::Simple;
use Config::Abstraction;
use Database::Abstraction;
use File::Basename;
# use CGI::Alert $ENV{'SERVER_ADMIN'} || 'you@example.com';
use FCGI;
use FCGI::Buffer;
use File::HomeDir;
use HTTP::Status;
use Log::Abstraction;
use Error qw(:try);
use File::Spec;
use POSIX qw(strftime);
use Readonly;
use Timer::Simple;
use Time::HiRes;

# FIXME: Sometimes gives Insecure dependency in require while running with -T switch in Module/Runtime.pm
# use Taint::Runtime qw($TAINT taint_env);
use autodie qw(:all);

# Where to find the Ged2site modules
# use lib '/usr/lib';	# This needs to point to the VWF directory lives,
			# i.e., the contents of the lib directory in the
			# distribution
use lib '../lib';
use lib CGI::Info::script_dir() . '/../lib';
use lib File::HomeDir->my_home() . '/lib/perl5';

use VWF::Allow;
use VWF::Blacklist;
use VWF::Config;
use VWF::Utils;
use Error::DB::Open;

# $TAINT = 1;
# taint_env();

# Set rate limit parameters
Readonly my $MAX_REQUESTS => 100;	# Default max requests allowed
Readonly my $TIME_WINDOW => '60s';	# Time window for the maximum requests

my $info = CGI::Info->new();
my $config;
my @suffixlist = ('.pl', '.fcgi');
my $script_name = basename($info->script_name(), @suffixlist);
my $tmpdir = $info->tmpdir();

if($ENV{'HTTP_USER_AGENT'}) {
	# open STDERR, ">&STDOUT";
	close STDERR;
	open(STDERR, '>>', File::Spec->catfile($tmpdir, "$script_name.stderr"));
}

Log::WarnDie->filter(\&filter);

my $vwflog;	# Location of the vwf.log file, read in from the config file - default = logdir/vwf.log

my $info_cache;
my $lingua_cache;
my $buffercache;

my $script_dir = $info->script_dir();
my $env_prefix = uc($info->host_name()) . '_';
$env_prefix =~ tr/\./_/;
my $logger = Log::Abstraction->new(Config::Abstraction->new(env_prefix => $env_prefix, flatten => 0, config_file => $info->domain_name() || 'default', config_dirs => ["$script_dir/../conf/", "$script_dir/../../conf"])->all());
Log::WarnDie->dispatcher($logger);

# my $pagename = "VWF::Display::$script_name";
# eval "require $pagename";

# Loaded later, only when needed
# use Ged2site::Display::home;
# use Ged2site::Display::people;
# use Ged2site::Display::censuses;
# use Ged2site::Display::surnames;
# use Ged2site::Display::history;
# use Ged2site::Display::todo;
# use Ged2site::Display::calendar;
# use Ged2site::Display::changes;
# use Ged2site::Display::descendants;
# use Ged2site::Display::graphs;
# use Ged2site::Display::emigrants;
# use Ged2site::Display::intermarriages;
# use Ged2site::Display::locations;
# use Ged2site::Display::orphans;
# use Ged2site::Display::ww1;
# use Ged2site::Display::ww2;
# use Ged2site::Display::military;
# use Ged2site::Display::twins;
# use Ged2site::Display::reports;
# use Ged2site::Display::facts;
# use Ged2site::Display::mailto;
# use Ged2site::Display::meta_data;

use Ged2site::DB::people;
use Ged2site::Data::changes;
use Ged2site::Data::censuses;
use Ged2site::Data::history;
use Ged2site::Data::orphans;
use Ged2site::DB::surnames;
use Ged2site::DB::intermarriages;
use Ged2site::DB::todo;
use Ged2site::DB::name_date;
use Ged2site::DB::surname_date;
use Ged2site::DB::twins;
use Ged2site::DB::military;
use Ged2site::DB::heritage;
use Ged2site::DB::locations;
use Ged2site::DB::places;
use Ged2site::Data::vwf_log;

my $database_dir = "$script_dir/../data";
Database::Abstraction::init({
	cache => CHI->new(driver => 'Memory', datastore => {}),
	cache_duration => '1 day',
	directory => $database_dir,
	logger => $logger
});

my $people = Ged2site::DB::people->new();
if($@) {
	$logger->error($@) if($logger);
	Log::WarnDie->dispatcher(undef);
	die $@;
}
my $censuses = Ged2site::Data::censuses->new();
my $changes = Ged2site::Data::changes->new(no_entry => 1);
my $surnames = Ged2site::DB::surnames->new();
my $history = Ged2site::Data::history->new(no_fixate => 1);
my $orphans = Ged2site::Data::orphans->new();
my $todo = Ged2site::DB::todo->new();
my $intermarriages = Ged2site::DB::intermarriages->new();
my $heritage = Ged2site::DB::heritage->new();
my $locations = Ged2site::DB::locations->new();
my $places = Ged2site::DB::places->new();
my $name_date = Ged2site::DB::name_date->new();
my $surname_date = Ged2site::DB::surname_date->new();
my $twins = Ged2site::DB::twins->new();
my $military = Ged2site::DB::military->new();

# http://www.fastcgi.com/docs/faq.html#PerlSignals
# Reader for the CSV access log, used by the meta_data page.  Created in doit()
# from the same path that vwflog() writes to, which needs $config.
my $vwf_log;

# The pages that may be loaded; worked out in doit() since it needs $config
my @valid_pages;

# FastCGI signal handling: the FCGI process lives across many requests so we
# cannot exit immediately on SIGTERM/SIGUSR1 — we set a flag and exit cleanly
# after the current request finishes.  See http://fastcgi.com/docs/faq.html#PerlSignals
my $requestcount = 0;
my $handling_request = 0;
my $exit_requested = 0;
my %blacklisted_ip;

# CHI->stats->enable();

my $rate_limit_cache;	# Rate limit clients by IP address
Readonly my @rate_limit_trusted_ips => ('127.0.0.1', '192.168.1.1');

# The CGI::ACL object is built on the first request, once $config is loaded,
# because the country blacklist (VWF::Blacklist) can come from the config file.
my $acl;

sub sig_handler {
	$exit_requested = 1;
	$logger->trace('In sig_handler');
	if(!$handling_request) {
		$logger->info('Shutting down');
		if($buffercache) {
			$buffercache->purge();
		}
		CHI->stats->flush();
		Log::WarnDie->dispatcher(undef);
		exit(0);
	}
}

$SIG{USR1} = \&sig_handler;
$SIG{TERM} = \&sig_handler;
$SIG{PIPE} = 'IGNORE';

# my ($stdin, $stdout, $stderr) = (IO::Handle->new(), IO::Handle->new(), IO::Handle->new());
# https://stackoverflow.com/questions/14563686/how-do-i-get-errors-in-from-a-perl-script-running-fcgi-pm-to-appear-in-the-apach
$SIG{__WARN__} = sub {
	my $msg = join '', @_;
	if(open(my $fout, '>>', File::Spec->catfile($tmpdir, "$script_name.stderr"))) {
		print $fout $info->domain_name(), ": $msg";
		close $fout;
	# } else {
		# print $stderr $msg;
	}
	$logger->warn($msg) if($logger);
};

$SIG{__DIE__} = sub {
	return if $^S;	# Let Error.pm try/catch handle dies inside eval blocks
	my $msg = join '', @_;
	Log::WarnDie->dispatcher(undef);
	if(open(my $fout, '>>', File::Spec->catfile($tmpdir, "$script_name.stderr"))) {
		print $fout $info->domain_name(), ": $msg";
		close $fout;
	# } else {
		# print $stderr $msg;
	}
	$logger->fatal($msg) if($logger);
	CORE::die @_;
};

# my $request = FCGI::Request($stdin, $stdout, $stderr);
my $request = FCGI::Request();

# Main request loop
while($handling_request = ($request->Accept() >= 0)) {
	unless($ENV{'REMOTE_ADDR'}) {
		# debugging from the command line
		my $timer = Timer::Simple->new();

		$ENV{'NO_CACHE'} = 1;
		if((!defined($ENV{'HTTP_ACCEPT_LANGUAGE'})) && defined($ENV{'LANG'})) {
			my $lang = $ENV{'LANG'};
			$lang =~ s/\..*$//;
			$lang =~ tr/_/-/;
			$ENV{'HTTP_ACCEPT_LANGUAGE'} = lc($lang);
		}

		Database::Abstraction::init({ logger => $logger });

		$logger = Log::Abstraction->new(logger => sub { print join(', ', @{$_[0]->{'message'}}), "\n" }, level => 'debug');
		Log::WarnDie->dispatcher($logger);
		$info->set_logger($logger);
		# TODO - set logger on all databases
		$info->set_logger($logger);
		$people->set_logger($logger);
		$heritage->set_logger($logger);
		$locations->set_logger($logger);
		$places->set_logger($logger);
		$vwf_log->set_logger($logger) if($vwf_log);
		# $Config::Auto::Debug = 1;

		$Error::Debug = 1;
		# CHI->stats->enable();
		try {
			doit(debug => 1);
		} catch Error with {
			my $msg = shift;
			warn "$msg\n", $msg->stacktrace();
			$logger->error($msg);
		};

		my @elapsed_time = $timer->hms();
		my $timetaken = int($elapsed_time[2] * 1000);
		$logger->info("$script_name completed in ${timetaken}ms");

		last;
	}

	$requestcount++;
	$logger->info("Request $requestcount: ", $ENV{'REMOTE_ADDR'});
	$info->set_logger($logger);
	$people->set_logger($logger);
	$heritage->set_logger($logger);
	$locations->set_logger($logger);
	$places->set_logger($logger);
	$vwf_log->set_logger($logger) if($vwf_log);

	# TODO:	Make this neater
	try {
		doit(debug => 0);
	} catch Error with {
		my $msg = shift;
		$logger->error("$msg: ", $msg->stacktrace());
		if($buffercache) {
			$buffercache->clear();
			$buffercache = undef;
		}
	};

	$request->Finish();

	$handling_request = 0;
	if($exit_requested) {
		last;
	}
	if($ENV{SCRIPT_FILENAME}) {
		if(-M $ENV{SCRIPT_FILENAME} < 0) {
			last;
		}
	}
}

# Clean up resources before shutdown
$logger->info('Shutting down');
if($buffercache) {
	$buffercache->purge();
}
if($rate_limit_cache) {
	# Memcached can't purge().
	# I don't like this hardwired code, it would be better if I could find a way to determine if a driver can run purge()
	$rate_limit_cache->purge() if($rate_limit_cache->short_driver_name() ne 'Memcached');
}
if($info_cache) {
	$info_cache->purge();
}
if($lingua_cache) {
	$lingua_cache->purge();
}
CHI->stats->flush();
Log::WarnDie->dispatcher(undef);
exit(0);

# Create and send response to the client for each request
sub doit
{
	my $request_start = Timer::Simple->new();

	CGI::Info->reset();

	# Call domain_name in a class context to ensure it's reread now that FCGI has started up
	$logger->debug('In doit - domain is ', CGI::Info->domain_name());

	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# $config is built once per process and reused.  We cannot build it before
	# the first Accept() because the domain name is not known until then.
	$config ||= VWF::Config->new({
		logger => $logger,
		info => $info,
		debug => $params{'debug'},
		lingua => CGI::Lingua->new({ supported => [ 'en-gb' ], info => $info, logger => $logger })	# Use a temporary CGI::Lingua
	});

	# deny_cloud() blocks all known cloud provider address ranges (AWS, GCP,
	# Azure) which generate almost no legitimate human traffic but are a
	# common origin for automated scanning.  Geo-blocking is a blunt
	# instrument but effective at reducing noise.
	$acl ||= CGI::ACL->new()
		->deny_cloud()
		->deny_country(country => VWF::Blacklist->new(countries => $config->{'blacklist_countries'})->countries())
		->allow_ip('108.44.193.70')
		->allow_ip('127.0.0.1');

	@valid_pages = valid_pages($config) unless(@valid_pages);
	# Stores things for a day or longer
	$info_cache ||= create_disc_cache(config => $config, logger => $logger, namespace => 'CGI::Info');

	my $options = {
		cache => $info_cache,
		logger => $logger
	};

	my $syslog;
	if($syslog = $config->syslog()) {
		if($syslog->{'server'}) {
			$syslog->{'host'} = delete $syslog->{'server'};
		}
		$options->{'syslog'} = $syslog;
	}
	$info = CGI::Info->new($options);

	# Configure cache for rate limiting
	$rate_limit_cache ||= create_memory_cache(config => $config, logger => $logger, namespace => 'rate_limit');

	# Get client IP
	my $client_ip = $ENV{'REMOTE_ADDR'} || 'unknown';

	# Check for CAPTCHA bypass token
	my $captcha_bypass_key = "$script_name:captcha_bypass:$client_ip";
	my $has_captcha_bypass = $rate_limit_cache->get($captcha_bypass_key);

	# Check and increment request count
	my $request_count = $rate_limit_cache->get("$script_name:rate_limit:$client_ip") || 0;

	# Allow the thresholds to be tuned via the config file; fall back to the
	# compile-time constants if the stanza is missing.
	my $max_requests = $config->{'security'}->{'rate_limiting'}->{'max_requests'} || $MAX_REQUESTS;
	my $max_requests_hard = $config->{'security'}->{'rate_limiting'}->{'max_requests_hard'} || ($max_requests * 1.5);

	# The rate-limit window, as a CHI duration for the counter's TTL, and in
	# seconds for the Retry-After header (RFC 9110 section 10.2.3)
	my $time_window = $config->{'security'}->{'rate_limiting'}->{'time_window'} || $TIME_WINDOW;
	my $retry_after = duration_seconds($time_window);

	# Check if this is a CAPTCHA verification attempt
	if ($info->param('g-recaptcha-response')) {
		require 'VWF::CAPTCHA';
		VWF::CAPTCHA->new();

		my $recaptcha_config = $config->recaptcha();
		if ($recaptcha_config && $recaptcha_config->{enabled}) {
			my $captcha = VWF::CAPTCHA->new(
				site_key => $recaptcha_config->{site_key},
				secret_key => $recaptcha_config->{secret_key},
				logger => $logger
			);

			if ($captcha->verify($info->param('g-recaptcha-response'), $client_ip)) {
				# CAPTCHA verified - grant bypass
				my $bypass_duration = $config->{'security'}->{'rate_limiting'}->{'captcha_bypass_duration'} || '300s';
				$rate_limit_cache->set($captcha_bypass_key, 1, $bypass_duration);
				$rate_limit_cache->set("$script_name:rate_limit:$client_ip", 0, '60s'); # Reset counter

				$logger->info("CAPTCHA verified for $client_ip - rate limit bypass granted");
				$has_captcha_bypass = 1;

				# Redirect to original page or home
				my $redirect_page = $info->param('page') || 'index';
				$info->status(302);
				print "Status: 302 Found\n",
					"Location: $ENV{SCRIPT_NAME}?page=$redirect_page\n\n";
				return;
			} else {
				$logger->warn("CAPTCHA verification failed for $client_ip");
				# Fall through to show CAPTCHA again
			}
		}
	}

	$vwflog ||= $config->vwflog() || File::Spec->catfile($info->logdir(), 'vwf.log');
	$vwf_log ||= VWF::Data::vwf_log->new({
		directory => dirname($vwflog),
		filename => basename($vwflog),
		no_entry => 1,
		logger => $logger,
	});
	my $log = Class::Simple->new();

	# Stores things for a month or longer
	$lingua_cache ||= create_disc_cache(config => $config, logger => $logger, namespace => 'CGI::Lingua');

	# Language negotiation
	my $lingua = CGI::Lingua->new({
		supported => [ 'en-gb' ],
		cache => $lingua_cache,
		info => $info,
		logger => $logger,
		debug => $params{'debug'},
		syslog => $syslog,
	});

	my $cachedir = $params{'cachedir'} || $config->{disc_cache}->{root_dir} || File::Spec->catfile($tmpdir, 'cache');

	# Rate limit by IP (unless bypassed)
	unless($has_captcha_bypass || grep { $_ eq $client_ip } @rate_limit_trusted_ips) {
		if ($request_count >= $max_requests_hard) {
			# Hard limit exceeded - show CAPTCHA with warning
			my $recaptcha_config = $config->recaptcha();

			if ($recaptcha_config && $recaptcha_config->{enabled}) {
				$logger->warn("Hard rate limit exceeded for $client_ip ($request_count requests)");
				$info->status(429);

				eval 'require VWF::Display::captcha';
				my $display = VWF::Display::captcha->new({
					cachedir => $cachedir,
					info => $info,
					logger => $logger,
					lingua => $lingua,
					config => $config,
				});

				print 'Status: 429 ', HTTP::Status::status_message(429), "\n";
				print $display->as_string({
					'Retry-After' => $retry_after,
					Retry_After => $retry_after,
					hard_block => 1,
					request_count => $request_count,
				});

				vwflog($vwflog, $info, $lingua, $syslog, 'Hard rate limit - CAPTCHA shown', $log, $request_start);
				return;
			}

			# No CAPTCHA to offer, so block until the window expires
			$logger->warn("Hard rate limit exceeded for $client_ip ($request_count requests)");
			$info->status(429);
			send_error(429, "Too many requests - try again later\n", "Retry-After: $retry_after\n");
			vwflog($vwflog, $info, $lingua, $syslog, 'Hard rate limit', $log, $request_start);
			return;
		} elsif ($request_count >= $max_requests) {
			# Soft limit exceeded - show CAPTCHA
			my $recaptcha_config = $config->recaptcha();

			if ($recaptcha_config && $recaptcha_config->{enabled}) {
				$logger->info("Soft rate limit exceeded for $client_ip ($request_count requests) - CAPTCHA challenge issued");
				$info->status(429);

				my $display = VWF::Display::captcha->new({
					cachedir => $cachedir,
					info => $info,
					logger => $logger,
					lingua => $lingua,
					config => $config,
				});

				# print "Pragma: no-cache\n\n";
				print $display->as_string({
					'Retry-After' => $retry_after,
					Retry_After => $retry_after,
					hard_block => 0,
					request_count => $request_count,
				});

				vwflog($vwflog, $info, $lingua, $syslog, 'Soft rate limit - CAPTCHA shown', $log, $request_start);
				return;
			}
		}
	}

	# Commit the incremented request count back to the sliding-window cache.
	# The TTL is the rate-limit window; the counter expires automatically.
	$rate_limit_cache->set("$script_name:rate_limit:$client_ip", $request_count + 1, $time_window);

	if(!defined($info->param('page'))) {
		$logger->info('No page given in ', $info->as_string());
		choose();
		return;
	}

	# Access control checks
	if(my $remote_addr = $ENV{'REMOTE_ADDR'}) {
		my $reason;
		if($acl->all_denied(lingua => $lingua)) {
			$reason = 'Denied by CGI::ACL';
		} elsif(blacklisted($info)) {
			$reason = 'Blacklisted for attempting to break in';
		} else {
			try {
				unless(VWF::Allow::allow({
					info   => $info,
					lingua => $lingua,
					logger => $logger,
					cache  => $rate_limit_cache,
					config => $config,
				})) {
					$reason = 'Blocked by VWF::Allow';
				}
			} catch Error with {
				$reason = shift;
			};
		}
		if($reason) {
			# Return a minimal plain-text 403 - no template rendering so that
			# a blocked attacker receives no information about site structure.
			send_error(403, "Access Denied\n");
			$logger->info("$remote_addr: access denied: $reason");
			$info->status(403);
			vwflog($vwflog, $info, $lingua, $syslog, $reason, $log, $request_start);
			return;
		}
	}

	my $args = {
		generate_etag => 1,
		generate_last_modified => 1,
		compress_content => 1,
		generate_304 => 1,
		info => $info,
		optimise_content => 1,
		logger => $logger,
		lint_content => $info->param('lint_content') // $params{'debug'},
		lingua => $lingua
	};

	if((!$info->is_search_engine()) && $config->root_dir() &&
	   ($info->param('page') ne 'home') &&
	   ((!defined($info->param('action'))) || ($info->param('action') ne 'send'))) {
		$args->{'save_to'} = {
			directory => File::Spec->catfile($config->root_dir(), 'save_to'),
			ttl => 3600 * 24,
			create_table => 1
		};
	}

	my $fb = FCGI::Buffer->new()->init($args);

	if($fb->can_cache()) {
		$buffercache ||= create_disc_cache(config => $config, logger => $logger, namespace => $script_name, root_dir => $cachedir);
		$fb->init(
			cache => $buffercache,
			# generate_304 => 0,
			cache_duration => '1 day',
		);
		if($fb->is_cached()) {
			return;
		}
	}

	my $display;
	my $invalidpage;

	$args = {
		cachedir => $cachedir,
		info => $info,
		logger => $logger,
		lingua => $lingua,
		config => $config,
		log => $log
	};

	# Display the requested page
	eval {
		my $page = $info->param('page');
		$page =~ s/#.*$//;
		$page =~ s/\\//g;	# I don't know what you're trying to escape or why, but I'm not going to let you
		if($page =~ /\//) {
			# Block "page=/etc/passwd" and "page=http://www.google.com"
			$logger->info("Blocking '/' in $page");
			$info->status(403);
			$log->status(403);
			$invalidpage = 1;
		} else {
			# Strip every non-word character so that the page name can only
			# contain [A-Za-z0-9_] - safe to use as a Perl package suffix.
			$page =~ s/\W//g;
			$page =~ s/\s//g;
		}

		if($invalidpage) {
			# Already rejected above
		} elsif(!grep { $_ eq $page } @valid_pages) {
			# Only pages on the allow-list are loaded, so that no other
			# Ged2site::Display::* module that happens to be on @INC (e.g. under
			# ~/lib/perl5) can be reached from the query string.
			$logger->info("Unknown page $page");
			$invalidpage = 1;
			if($info->status() == 200) {
				$info->status(404);
			}
		} else {
			my $display_module = "Ged2site::Display::$page";

			$logger->debug("doit(): Loading module $display_module from @INC");
			unless($display_module->can('new')) {
				# String-eval elimination:
				#   The original code used eval "require $display_module" which is a
				#   string eval on a user-derived value.  Although $page has been
				#   stripped of \W characters, a Unicode or locale edge-case could
				#   allow a bypass.  Module::Runtime::require_module() loads a module
				#   by name using a block eval internally, with no string-eval surface.
				eval { require_module($display_module) };
				$display_module->import() unless $@;
			}
			if($@) {
				$logger->debug("Failed to load module $display_module: $@");
				$logger->info("Unknown page $page");
				$invalidpage = 1;
				if($info->status() == 200) {
					$info->status(404);
				}
			} else {
				# use Class::Inspector;
				# my $methods = Class::Inspector->methods($display_module);
				# print "$display_module exports ", join(', ', @{$methods}), "\n";
				$display = do {
					eval { $display_module->new($args) };
				};
				if(!defined($display)) {
					if($@) {
						$logger->warn("$display_module->new(): $@");
					} else {
						$logger->notice("Can't instantiate page $page");
					}
					$invalidpage = 1;
					if($info->status() == 200) {
						$info->status(404);
					}
				} elsif(!$display->can('as_string')) {
					$logger->warn("Problem understanding $page");
					undef $display;
				}
			}
		}
	};

	my $error = $@;
	if($error) {
		if($info->status() == 429) {
			$logger->notice($error);
		} else {
			$logger->error($error);
		}
		$display = undef;
	}

	if(defined($display)) {
		# Pass in handles to the databases
		print $display->as_string({
			cachedir => $cachedir,
			config => $config,
			databasedir => $database_dir,
			database_dir => $database_dir,
			people => $people,
			censuses => $censuses,
			changes => $changes,
			heritage => $heritage,
			locations => $locations,
			orphans => $orphans,
			places => $places,
			surnames => $surnames,
			history => $history,
			intermarriages => $intermarriages,
			todo => $todo,
			name_date => $name_date,
			surname_date => $surname_date,
			twins => $twins,
			military => $military,
			vwf_log => $vwf_log,
		});
		vwflog($vwflog, $info, $lingua, $syslog, '', $log, $request_start);
	} elsif($invalidpage) {
		if($info->status() == 429) {
			# Throttled by VWF::Display
			my $interval = $config->{'throttle'}->{'interval'} // 90;
			send_error(429, "Too many requests - try again later\n", "Retry-After: $interval\n");
			vwflog($vwflog, $info, $lingua, $syslog, 'Throttled', $log, $request_start);
		} else {
			choose();
			vwflog($vwflog, $info, $lingua, $syslog, 'Unknown page', $log, $request_start);
		}
		return;
	} else {
		$logger->debug('disabling cache');
		$fb->init(
			cache => undef,
		);
		# Handle errors gracefully
		my ($status, $body);
		if($error eq 'Unknown page to display') {
			($status, $body) = (400, "I don't know what you want me to display.\n");
		} elsif($error =~ /Can\'t locate .* in \@INC/) {
			$logger->error($error);
			($status, $body) = (500, "Software error - contact the webmaster\n");
		} elsif(($info->status() == 200) || ($info->status() == 403)) {
			# No permission to show this page
			($status, $body) = (403, "Access Denied\n");
		} else {
			$status = $info->status();
			$body = "Page unavailable - something is wrong at your end, please fix and try again\n";
		}
		send_error($status, $body);
		$info->status($status);
		$log->status($status);
		vwflog($vwflog, $info, $lingua, $syslog, $error ? $error : 'Access denied', $log, $request_start);
		throw Error::Simple($error ? $error : $info->as_string());
	}
}

sub choose
{
	$logger->info('Called with no page to display');

	my $status = $info->status();

	if($status != 200) {
		print "Status: $status ",
			HTTP::Status::status_message($status),
			"\n\n";
		return;
	}

	print "Status: 300 Multiple Choices\n",
		"Content-type: text/plain\n";

	$info->status(300);

	# Print last modified date if path is defined
	if(my $path = $info->script_path()) {
		require HTTP::Date;
		HTTP::Date->import();

		my @statb = stat($path);
		my $mtime = $statb[9];
		print 'Last-Modified: ', HTTP::Date::time2str($mtime), "\n";
	}

	print "\n";

	# RFC 7231 §4.3.2: a HEAD response must not include a body.
	unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		# The same list that doit() allows, so the two cannot differ
		print map { "/cgi-bin/page.fcgi?page=$_\n" } @valid_pages;
	}
}

# Send a short plain-text error response.  $extra_headers, if given, is one or
# more complete header lines (each ending in "\n") to add, e.g. Retry-After.
sub send_error
{
	my ($status, $body, $extra_headers) = @_;

	print "Status: $status ", HTTP::Status::status_message($status), "\n",
		$extra_headers // '',
		"Content-type: text/plain\n",
		"Pragma: no-cache\n\n";

	# RFC 9110 §9.3.2: a HEAD response must not include a body.
	my $is_head = $ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD');
	print $body if(defined($body) && !$is_head);

	return 1;
}

# The pages that ?page= may load.  Sites can list them in the config file
# (<pages>index, meta_data</pages>); otherwise every ../lib/VWF/Display/*.pm
# next to this script is allowed, except captcha, which only the rate limiter
# shows.
sub valid_pages
{
	my $config = shift;

	if(my $pages = $config->{'pages'}) {
		$pages = [split /[\s,]+/, $pages] unless(ref($pages));
		return grep { /\A\w+\z/ } @{$pages};
	}

	my $dir = File::Spec->catdir($script_dir, File::Spec->updir(), 'lib', 'VWF', 'Display');
	return sort(grep { $_ ne 'captcha' } map { basename($_, '.pm') } glob(File::Spec->catfile($dir, '*.pm')));
}

# Convert a CHI-style duration ('60s', '2 minutes', '90') to whole seconds
sub duration_seconds
{
	my $duration = shift;

	return $duration if($duration =~ /\A\d+\z/);

	require Time::Duration::Parse;

	my $seconds = eval { Time::Duration::Parse::parse_duration($duration) };
	if(!defined($seconds)) {
		$logger->warn("Can't parse duration '$duration', using 60 seconds");
		return 60;
	}
	return int($seconds);
}

# Is this client trying to attack us?
sub blacklisted
{
	if(my $remote = $ENV{'REMOTE_ADDR'}) {
		my $info = shift;
		if($blacklisted_ip{$remote}) {
			$info->status(403);
			return 1;
		}

		if(my $string = $info->as_string()) {
			# SECURITY - ReDoS defence:
			#   The original patterns used greedy .+ between SQL keywords, which
			#   causes catastrophic (exponential) backtracking when an attacker
			#   sends a string that contains the opening keyword but not the
			#   closing one (e.g. thousands of chars after SELECT with no AND).
			#   All .+ quantifiers are replaced with the bounded class [^;]{0,N}:
			#     - the semicolon is a natural SQL statement terminator so it is
			#       a safe anchor that real SQL injection never crosses, and
			#     - the explicit upper bound caps backtracking to O(N) steps.
			#   Word-boundary assertions (\b) also eliminate false positives on
			#   ordinary words that happen to contain the substring.
			if(   ($string =~ /SELECT\b[^;]{0,500}\bAND\b/i)
			   || ($string =~ /ORDER\s+BY\s/i)
			   || ($string =~ /\bOR\s+NOT\b/i)
			   || ($string =~ /\bAND\s+\d+=\d+/i)
			   || ($string =~ /\bTHEN\b[^;]{0,200}\bELSE\b[^;]{0,200}\bEND\b/i)
			   || ($string =~ /\bAND\b[^;]{0,200}\bSELECT\b/i)
			   || ($string =~ /\sAND\s[^;]{0,100}\sAND\s/i)
			   || ($string =~ /\bAND\s+CASE\s+WHEN\b/i)) {
				$blacklisted_ip{$remote} = 1;
				$info->status(403);
				return 1;
			}
		}
	}
	return 0;
}

# False positives we don't need in the logs
sub filter
{
	# return 0 if($_[0] =~ /Can't locate Net\/OAuth\/V1_0A\/ProtectedResourceRequest.pm in /);
	# return 0 if($_[0] =~ /Can't locate auto\/NetAddr\/IP\/InetBase\/AF_INET6.al in /);
	# return 0 if($_[0] =~ /S_IFFIFO is not a valid Fcntl macro at /);

	return 0 if $_[0] =~ /Can't locate (Net\/OAuth\/V1_0A\/ProtectedResourceRequest\.pm|auto\/NetAddr\/IP\/InetBase\/AF_INET6\.al) in |S_IFFIFO is not a valid Fcntl macro at /;
	return 1;
}

# Escape a single value for safe inclusion in a double-quoted CSV field.
# Follows RFC 4180 §2.7 and additionally neutralises spreadsheet formulas.
sub _csv_escape
{
	my $v = shift // '';

	# RFC 4180: a double-quote inside a quoted field is represented by two
	# double-quote characters.  Without this, one embedded " would break the
	# column boundary and corrupt every subsequent field on the row.
	$v =~ s/"/""/g;

	# SECURITY - CSV formula injection defence:
	#   Spreadsheet applications (Excel, LibreOffice Calc) interpret cell values
	#   that begin with = + - @ TAB or CR as formulas.  An attacker who controls
	#   a logged field (e.g. the page parameter) could inject =cmd|'/C calc'!A0.
	#   Prefix such values with a single-quote to force literal interpretation.
	$v =~ s/^([=+\-@\t\r])/'$1/;

	return $v;
}

# Write one access record to vwf.log (CSV format) and optionally to syslog.
# All user-influenced fields are escaped through _csv_escape before output.
sub vwflog
{
	my ($vwflog, $info, $lingua, $syslog, $message, $log, $request_start) = @_;

	# Calculate request duration in milliseconds if a start timer was supplied.
	my $duration_ms = '';
	if($request_start) {
		$duration_ms = int((Time::HiRes::time() - $request_start) * 1000);
	}

	# Determine which template was rendered for this request (may be empty on error).
	my $template;
	if($log) {
		$template = $log->template();
	}
	if(!defined($template)) {
		$template = '';
	}
	$message ||= '';

	# Create the log file with a header row on first use.
	if(!-e $vwflog) {
		open(my $fout, '>', $vwflog);
		print $fout '"domain_name","time","IP","country","type","language","http_code","template","args","messages","error","duration_ms"',
			"\n";
		close $fout;
	}

	# Collect any warn/notice-level messages emitted during this request.
	my $warnings;
        if(my $messages = $info->messages()) {
                $warnings = join('; ',
                        grep defined, map { (($_->{'level'} eq 'warn') || ($_->{'level'} eq 'notice')) ? $_->{'message'} : undef } @{$messages}
                        )
        }
	$warnings ||= '';

	my $country = $lingua->country() || 'unknown';

	# Open the log in append mode.  If the open fails we skip logging silently
	# so that a disk-full or permissions error does not crash the live request.
	if(open(my $fout, '>>', $vwflog)) {
		# SECURITY — CSV injection defence:
		#   Every user-visible field is passed through _csv_escape so that
		#   embedded double-quotes cannot break the CSV column structure, and
		#   leading formula characters cannot trigger code execution when the
		#   file is opened in a spreadsheet application.
		print $fout
			'"', _csv_escape($info->domain_name()), '",',
			'"', strftime('%F %T', localtime), '",',
			'"', _csv_escape($ENV{REMOTE_ADDR} // ''), '",',
			'"', _csv_escape($country), '",',
			'"', _csv_escape($info->browser_type()), '",',
			'"', _csv_escape($lingua->language() // ''), '",',
			$info->status(), ',',
			'"', _csv_escape($template), '",',
			'"', _csv_escape($info->as_string(raw => 1)), '",',
			'"', _csv_escape($warnings), '",',
			'"', _csv_escape($message), '",',
			$duration_ms,
			"\n";
		close($fout);
	}

	# Optionally mirror the record to syslog (configured via the syslog stanza).
	if($syslog) {
		unless(Sys::Syslog->can('openlog')) {
			require Sys::Syslog;
			Sys::Syslog->import();
		}

		# Configure the socket transport if a hash of options was provided.
		if(ref($syslog) eq 'HASH') {
			Sys::Syslog::setlogsock($syslog);
		}
		Sys::Syslog::openlog($script_name, 'cons,pid', 'user');
		# Use positional %s/%d format args so that special characters in the
		# values cannot be interpreted as syslog format directives.
		Sys::Syslog::syslog('info|local0', '%s %s %s %s %s %d %s %s %d %s %s',
			$info->domain_name() || '',
			$ENV{REMOTE_ADDR} || '',
			$country,
			$info->browser_type() || '',
			$lingua->language() || '',
			$info->status() || '',
			$template || '',
			$info->as_string(raw => 1) || '',
			$duration_ms,
			$warnings,
			$message
		);
		Sys::Syslog::closelog();
	}
}
