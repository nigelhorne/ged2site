#!/usr/bin/env perl

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# Can be tested at the command line, e.g.:
#	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi page=index
# To mimic a French mobile site:
#	root_dir=$(pwd)/.. ./page.fcgi --mobile page=index lang=fr
# To turn off the linting of HTML on a search engine landing page
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
use CGI::ACL;
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

use Ged2site::Config;
use Ged2site::Utils;
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
my $logger = Log::Abstraction->new(Config::Abstraction->new(env_prefix => $env_prefix, flatten => 0, config_file => 'example.com', config_dirs => ["$script_dir/../conf/", "$script_dir/../../conf"])->all());
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
if($@) {
	$logger->error($@) if($logger);
	Log::WarnDie->dispatcher(undef);
	die $@;
}
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
my $locations = Ged2site::DB::locations->new();
my $places = Ged2site::DB::places->new();
my $name_date = Ged2site::DB::name_date->new();
my $surname_date = Ged2site::DB::surname_date->new();
my $twins = Ged2site::DB::twins->new();
my $military = Ged2site::DB::military->new();

# FIXME - support $config->vwflog();
my $vwf_log = Ged2site::Data::vwf_log->new({ directory => $info->logdir(), filename => 'vwf.log', no_entry => 1 });

# http://www.fastcgi.com/docs/faq.html#PerlSignals
my $requestcount = 0;
my $handling_request = 0;
my $exit_requested = 0;
my %blacklisted_ip;

# CHI->stats->enable();

my $rate_limit_cache;	# Rate limit clients by IP address
Readonly my @rate_limit_trusted_ips => ('127.0.0.1', '192.168.1.1');

Readonly my @blacklist_country_list => (
	'BY', 'MD', 'RU', 'CN', 'BR', 'UY', 'TR', 'MA', 'VE', 'SA', 'CY',
	'CO', 'MX', 'IN', 'RS', 'PK', 'UA', 'XH'
);

my $acl = CGI::ACL->new()->deny_country(country => \@blacklist_country_list)->allow_ip('108.44.193.70')->allow_ip('127.0.0.1');

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
$SIG{__DIE__} = $SIG{__WARN__} = sub {
	my $msg = join '', @_;
	Log::WarnDie->dispatcher(undef);
	if(open(my $fout, '>>', File::Spec->catfile($tmpdir, "$script_name.stderr"))) {
		print $fout $info->domain_name(), ": $msg";
		close $fout;
	# } else {
		# print $stderr $msg;
	}
	$logger->fatal($msg) if($logger);
	CORE::die $msg;
};

# my $request = FCGI::Request($stdin, $stdout, $stderr);
my $request = FCGI::Request();

# Main request loop
while($handling_request = ($request->Accept() >= 0)) {
	unless($ENV{'REMOTE_ADDR'}) {
		# debugging from the command line
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
		$people->set_logger($logger);
		$vwf_log->set_logger($logger);
		# $Config::Auto::Debug = 1;

		# TODO:  Make this neater
		# Tries again without the database if it can't be opened
		$Error::Debug = 1;
		# CHI->stats->enable();
		try {
			doit(debug => 1);
		} catch Error::DB::Open with {
			my $msg = shift;
			my $tryagain = 0;
			my $file = $msg->{'-file'};
			if($file =~ /locations/) {
				# The locations database doesn't exist
				$locations = undef;
				$tryagain = 1;
			} elsif($file =~ /censuses/) {
				# The census database doesn't exist
				$censuses = undef;
				$tryagain = 1;
			} elsif($file =~ /military/) {
				# The military database doesn't exist
				$military = undef;
				$tryagain = 1;
			}
			if($tryagain) {
				try {
					doit(debug => 1);
				} catch Error with {
					$msg = shift;
					warn "$msg\n", $msg->stacktrace();
					$logger->error($msg);
				};
			} else {
				warn "$msg\n", $msg->stacktrace();
				$logger->error($msg);
			}
		} catch Error with {
			my $msg = shift;
			warn "$msg\n", $msg->stacktrace();
			$logger->error($msg);
		};
		last;
	}

	$requestcount++;
	$logger->info("Request $requestcount: ", $ENV{'REMOTE_ADDR'});
	$info->set_logger($logger);
	$people->set_logger($logger);
	$locations->set_logger($logger);
	$places->set_logger($logger);
	$vwf_log->set_logger($logger);

	my $start = [Time::HiRes::gettimeofday()];

	# TODO:  Make this neater
	# Tries again without the database if it can't be opened
	try {
		doit(debug => 0);
		my $timetaken = Time::HiRes::tv_interval($start);

		$logger->info("$script_name completed in $timetaken seconds");
	} catch Error::DB::Open with {
		my $msg = shift;
		my $tryagain = 0;
		my $file = $msg->{'-file'};
		if($file =~ /locations/) {
			# The locations database doesn't exist
			$locations = undef;
			$tryagain = 1;
		} elsif($file =~ /censuses/) {
			# The census database doesn't exist
			$censuses = undef;
			$tryagain = 1;
		} elsif($file =~ /military/) {
			# The military database doesn't exist
			$military = undef;
			$tryagain = 1;
		}
		if($tryagain) {
			try {
				doit(debug => 0);
			} catch Error with {
				$msg = shift;
				warn "$msg\n", $msg->stacktrace();
				$logger->error($msg);
			};
		} else {
			warn "$msg\n", $msg->stacktrace();
			$logger->error($msg);
			if($buffercache) {
				$buffercache->clear();
				$buffercache = undef;
			}
		}
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
	my $request_start = Time::HiRes::time();

	CGI::Info->reset();

	# Call domain_name in a class context to ensure it's reread now that FCGI has started up
	$logger->debug('In doit - domain is ', CGI::Info->domain_name());

	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Don't pass $info in since it was created before the connection, so it doesn't know the domain name
	#	config file to read
	$config ||= Ged2site::Config->new({
		logger => $logger,
		debug => $params{'debug'},
		lingua => CGI::Lingua->new({ supported => [ 'en-gb' ], info => $info, logger => $logger })	# Use a temporary CGI::Lingua
	});

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

	# Get rate limit thresholds
	my $max_requests = $config->{'security'}->{'rate_limiting'}->{'max_requests'} || $MAX_REQUESTS;
	my $max_requests_hard = $config->{'security'}->{'rate_limiting'}->{'max_requests_hard'} || ($max_requests * 1.5);

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

	# TODO: update the vwf_log variable to point here
	$vwflog ||= $config->vwflog() || File::Spec->catfile($info->logdir(), 'vwf.log');
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

				# print "Pragma: no-cache\n\n";
				print $display->as_string({
					Retry_After => 60,
					hard_block => 1,
					request_count => $request_count,
				});

				vwflog($vwflog, $info, $lingua, $syslog, 'Hard rate limit - CAPTCHA shown', $log, $request_start);
				return;
			}
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
					Retry_After => 60,
					hard_block => 0,
					request_count => $request_count,
				});

				vwflog($vwflog, $info, $lingua, $syslog, 'Soft rate limit - CAPTCHA shown', $log, $request_start);
				return;
			}
		}
	}

	# Increment request count
	my $time_window = $config->{'security'}->{'rate_limiting'}->{'time_window'} || $TIME_WINDOW;
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
		}
		if($reason) {
			# Client has been blocked
			print "Status: 403 Forbidden\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Access Denied\n";
			}
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
			# Remove all non alphanumeric characters in the name of the page to be loaded
			$page =~ s/\W//g;
			$page =~ s/\s//g;
			my $display_module = "Ged2site::Display::$page";

			# TODO: consider creating a whitelist of valid modules
			$logger->debug("doit(): Loading module $display_module from @INC");
			eval "require $display_module";
			if($@) {
				$logger->debug("Failed to load module $display_module: $@");
				$logger->info("Unknown page $page");
				$invalidpage = 1;
				if($info->status() == 200) {
					$info->status(404);
				}
			} else {
				$display_module->import();
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
		choose();
		vwflog($vwflog, $info, $lingua, $syslog, 'Unknown page', $log, $request_start);
		return;
	} else {
		$logger->debug('disabling cache');
		$fb->init(
			cache => undef,
		);
		# Handle errors gracefully
		if($error eq 'Unknown page to display') {
			print "Status: 400 Bad Request\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "I don't know what you want me to display.\n";
			}
			$info->status(400);
			$log->status(400);
		} elsif($error =~ /Can\'t locate .* in \@INC/) {
			$logger->error($error);
			print "Status: 500 Internal Server Error\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Software error - contact the webmaster\n";
			}
			$info->status(500);
			$log->status(500);
		} elsif(($info->status() == 200) || ($info->status() == 403)) {
			# No permission to show this page
			print "Status: 403 Forbidden\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Access Denied\n";
			}
			$info->status(403);
			$log->status(403);
		} else {
			my $status = $info->status();
			print "Status: $status ",
				HTTP::Status::status_message($status),
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Page unavailable - something is wrong at your end, please fix and try again\n";
			}
			$log->status($status);
		}
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

	# Print available pages unless it's a HEAD request
	unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		print "/cgi-bin/page.fcgi?page=people\n",
			"/cgi-bin/page.fcgi?page=ancestors\n",
			"/cgi-bin/page.fcgi?page=home\n",
			"/cgi-bin/page.fcgi?page=censuses\n",
			"/cgi-bin/page.fcgi?page=changes\n",
			"/cgi-bin/page.fcgi?page=surnames\n",
			"/cgi-bin/page.fcgi?page=history\n",
			"/cgi-bin/page.fcgi?page=todo\n",
			"/cgi-bin/page.fcgi?page=calendar\n",
			"/cgi-bin/page.fcgi?page=descendants\n",
			"/cgi-bin/page.fcgi?page=graphs\n",
			"/cgi-bin/page.fcgi?page=emigrants\n",
			"/cgi-bin/page.fcgi?page=intermarriages\n",
			"/cgi-bin/page.fcgi?page=ww1\n",
			"/cgi-bin/page.fcgi?page=ww2\n",
			"/cgi-bin/page.fcgi?page=military\n",
			"/cgi-bin/page.fcgi?page=orphans\n",
			"/cgi-bin/page.fcgi?page=twins\n",
			"/cgi-bin/page.fcgi?page=reports\n",
			"/cgi-bin/page.fcgi?page=facts\n",
			"/cgi-bin/page.fcgi?page=mailto\n",
			"/cgi-bin/page.fcgi?page=meta_data\n",
			"/cgi-bin/page.fcgi?page=xml\n";
	}
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
			if(($string =~ /SELECT.+AND.+/i) || ($string =~ /ORDER BY /i) || ($string =~ / OR NOT /i) || ($string =~ / AND \d+=\d+/i) || ($string =~ /THEN.+ELSE.+END/i) || ($string =~ /.+AND.+SELECT.+/i) || ($string =~ /\sAND\s.+\sAND\s/i) || ($string =~ /AND\sCASE\sWHEN/i)) {
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

# Put something to vwf.log
sub vwflog
{
	my ($vwflog, $info, $lingua, $syslog, $message, $log, $request_start) = @_;

	my $duration_ms = '';
	if($request_start) {
		$duration_ms = int((Time::HiRes::time() - $request_start) * 1000);
	}

	my $template;
	if($log) {
		$template = $log->template();
	}
	if(!defined($template)) {
		$template = '';
	}
	$message ||= '';

	if(!-e $vwflog) {
		# First run - put in the heading row
		open(my $fout, '>', $vwflog);
		print $fout '"domain_name","time","IP","country","type","language","http_code","template","args","messages","error","duration_ms"',
			"\n";
		close $fout;
	}

	my $warnings;
        if(my $messages = $info->messages()) {
                $warnings = join('; ',
                        grep defined, map { (($_->{'level'} eq 'warn') || ($_->{'level'} eq 'notice')) ? $_->{'message'} : undef } @{$messages}
                        )
        }
	$warnings ||= '';

	if(open(my $fout, '>>', $vwflog)) {
		print $fout
			'"', $info->domain_name(), '",',
			'"', strftime('%F %T', localtime), '",',
			'"', ($ENV{REMOTE_ADDR} ? $ENV{REMOTE_ADDR} : ''), '",',
			'"', $lingua->country(), '",',
			'"', $info->browser_type(), '",',
			'"', $lingua->language(), '",',
			$info->status(), ',',
			'"', $template, '",',
			'"', $info->as_string(raw => 1), '",',
			'"', $warnings, '",',
			'"', $message, '",',
			$duration_ms,
			"\n";
		close($fout);
	}

	if($syslog) {
		unless(Sys::Syslog->can('openlog')) {
			require Sys::Syslog;
			Sys::Syslog->import();
		}

		if(ref($syslog) eq 'HASH') {
			Sys::Syslog::setlogsock($syslog);
		}
		Sys::Syslog::openlog($script_name, 'cons,pid', 'user');
		Sys::Syslog::syslog('info|local0', '%s %s %s %s %s %d %s %s %d %s %s',
			$info->domain_name() || '',
			$ENV{REMOTE_ADDR} || '',
			$lingua->country() || '',
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
