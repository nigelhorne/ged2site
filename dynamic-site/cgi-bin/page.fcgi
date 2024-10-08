#!/usr/bin/env perl

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# Can be tested at the command line, e.g.:
#	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi page=home
# To mimic a French mobile site:
#	root_dir=$(pwd)/.. ./page.fcgi mobile=1 page=home lang=fr
# To turn off linting of HTML on a search-engine landing page
#	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi --search-engine page=home lint_content=0

use strict;
use warnings;
# use diagnostics;

no lib '.';

use Log::Log4perl qw(:levels);	# Put first to cleanup last
use CGI::Carp qw(fatalsToBrowser);
use CGI::Info;
use CGI::Lingua 0.61;
use Database::Abstraction 0.05;
use File::Basename;
# use CGI::Alert $ENV{'SERVER_ADMIN'} || 'you@example.com';
use FCGI;
use FCGI::Buffer;
use File::HomeDir;
use Log::Any::Adapter;
use Error qw(:try);
use File::Spec;
use Log::WarnDie 0.09;
use CGI::ACL;
use HTTP::Date;
use POSIX qw(strftime);
use Time::HiRes;
# FIXME: Gives Insecure dependency in require while running with -T switch in Module/Runtime.pm
# use Taint::Runtime qw($TAINT taint_env);
use autodie qw(:all);

# use lib '/usr/lib';	# This needs to point to the Ged2site directory lives,
			# i.e. the contents of the lib directory in the
			# distribution
use lib '../lib';

use Ged2site::Config;
use Error::DB::Open;

# $TAINT = 1;
# taint_env();

my $info = CGI::Info->new();
my $script_dir = $info->script_dir();
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

my $vwflog = File::Spec->catfile($info->logdir(), 'vwf.log');

my $infocache;
my $linguacache;
my $buffercache;

Log::Log4perl->init("$script_dir/../conf/$script_name.l4pconf");
my $logger = Log::Log4perl->get_logger($script_name);
Log::WarnDie->dispatcher($logger);

# my $pagename = "Ged2site::Display::$script_name";
# eval "require $pagename";
use Ged2site::Display::home;
use Ged2site::Display::people;
use Ged2site::Display::censuses;
use Ged2site::Display::surnames;
use Ged2site::Display::history;
use Ged2site::Display::todo;
use Ged2site::Display::calendar;
use Ged2site::Display::changes;
use Ged2site::Display::descendants;
use Ged2site::Display::graphs;
use Ged2site::Display::emmigrants;
use Ged2site::Display::intermarriages;
use Ged2site::Display::locations;
use Ged2site::Display::orphans;
use Ged2site::Display::ww1;
use Ged2site::Display::ww2;
use Ged2site::Display::military;
use Ged2site::Display::twins;
use Ged2site::Display::reports;
use Ged2site::Display::facts;
use Ged2site::Display::mailto;
use Ged2site::Display::meta_data;

use Ged2site::DB::people;
if($@) {
	$logger->error($@);
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

my $database_dir = "$script_dir/../data";
Database::Abstraction::init({
	cache => CHI->new(driver => 'Memory', datastore => {}),
	cache_duration => '1 day',
	directory => $database_dir,
	logger => $logger
});

my $people = Ged2site::DB::people->new();
if($@) {
	$logger->error($@);
	die $@;
}
my $censuses = Ged2site::Data::censuses->new();
my $changes = Ged2site::Data::changes->new();
my $surnames = Ged2site::DB::surnames->new();
my $history = Ged2site::Data::history->new();
my $orphans = Ged2site::Data::orphans->new();
my $todo = Ged2site::DB::todo->new();
my $intermarriages = Ged2site::DB::intermarriages->new();
# TODO: why are these arguments needed?
my $locations = Ged2site::DB::locations->new(directory => $database_dir, logger => $logger);
my $name_date = Ged2site::DB::name_date->new();
my $surname_date = Ged2site::DB::surname_date->new();
my $twins = Ged2site::DB::twins->new();
my $military = Ged2site::DB::military->new();

# http://www.fastcgi.com/docs/faq.html#PerlSignals
my $requestcount = 0;
my $handling_request = 0;
my $exit_requested = 0;

# CHI->stats->enable();

my $acl = CGI::ACL->new()->deny_country(country => ['RU', 'CN'])->allow_ip('131.161.0.0/16')->allow_ip('127.0.0.1');

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
$ENV{'PATH'} = '/usr/local/bin:/bin:/usr/bin';	# For insecurity

$SIG{__WARN__} = sub { Log::WarnDie->dispatcher(undef); die @_ };

my $request = FCGI::Request();

# It would be really good to send 429 to search engines when there are more than, say, 5 requests being handled.
# But I don't think that's possible with the FCGI module

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
		Log::Any::Adapter->set('Stdout', log_level => 'trace');
		$logger = Log::Any->get_logger(category => $script_name);
		Log::WarnDie->dispatcher($logger);
		$people->set_logger($logger);
		$name_date->set_logger($logger);
		$surname_date->set_logger($logger);
		$info->set_logger($logger);
		# $Config::Auto::Debug = 1;

		# TODO:  Make this neater
		# Tries again without the database if it can't be opened
		$Error::Debug = 1;
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
	Log::Any::Adapter->set( { category => $script_name }, 'Log4perl');
	$logger = Log::Any->get_logger(category => $script_name);
	$logger->info("Request $requestcount: ", $ENV{'REMOTE_ADDR'});
	$people->set_logger($logger);
	$info->set_logger($logger);

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

$logger->info("Shutting down");
if($buffercache) {
	$buffercache->purge();
}
CHI->stats->flush();
Log::WarnDie->dispatcher(undef);
exit(0);

sub doit
{
	CGI::Info->reset();

	$logger->debug('In doit - domain is ', $info->domain_name());

	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
	$config ||= Ged2site::Config->new({ logger => $logger, info => $info, debug => $params{'debug'} });
	$infocache ||= create_memory_cache(config => $config, logger => $logger, namespace => 'CGI::Info');

	my $options = {
		cache => $infocache,
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

	if(!defined($info->param('page'))) {
		$logger->info('No page given in ', $info->as_string());
		choose();
		return;
	}

	$linguacache ||= create_memory_cache(config => $config, logger => $logger, namespace => 'CGI::Lingua');

	my $lingua = CGI::Lingua->new({
		supported => [ 'en-gb', 'fr' ],
		cache => $linguacache,
		info => $info,
		logger => $logger,
		debug => $params{'debug'},
		syslog => $syslog,
	});

	if($vwflog && open(my $fout, '>>', $vwflog)) {
		print $fout
			'"', $info->domain_name(), '",',
			'"', strftime('%F %T', localtime), '",',
			'"', ($ENV{REMOTE_ADDR} ? $ENV{REMOTE_ADDR} : ''), '",',
			'"', $lingua->country(), '",',
			'"', $info->browser_type(), '",',
			'"', $lingua->language(), '",',
			'"', $info->as_string(), "\"\n";
		close($fout);
	}

	if($ENV{'REMOTE_ADDR'} && $acl->all_denied(lingua => $lingua)) {
		print "Status: 403 Forbidden\n",
			"Content-type: text/plain\n",
			"Pragma: no-cache\n\n";

		unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
			print "Access Denied\n";
		}
		$logger->info($ENV{'REMOTE_ADDR'}, ': access denied');
		return;
	}

	my $args = {
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

	my $cachedir = $params{'cachedir'} || $config->{disc_cache}->{root_dir} || File::Spec->catfile($tmpdir, 'cache');

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
	};
	eval {
		my $page = $info->param('page');
		$page =~ s/#.*$//;
		# $display = Ged2site::Display::$page->new($args);
		if($page eq 'people') {
			$display = Ged2site::Display::people->new($args);
		} elsif($page eq 'censuses') {
			$display = Ged2site::Display::censuses->new($args);
		} elsif($page eq 'surnames') {
			$display = Ged2site::Display::surnames->new($args);
		} elsif($page eq 'history') {
			$display = Ged2site::Display::history->new($args);
		} elsif($page eq 'todo') {
			$display = Ged2site::Display::todo->new($args);
		} elsif($page eq 'calendar') {
			$display = Ged2site::Display::calendar->new($args);
		} elsif($page eq 'changes') {
			$display = Ged2site::Display::changes->new($args);
		} elsif($page eq 'descendants') {
			$display = Ged2site::Display::descendants->new($args);
		} elsif($page eq 'graphs') {
			$display = Ged2site::Display::graphs->new($args);
		} elsif($page eq 'emmigrants') {
			$display = Ged2site::Display::emmigrants->new($args);
		} elsif($page eq 'intermarriages') {
			$display = Ged2site::Display::intermarriages->new($args);
		} elsif($page eq 'locations') {
			$display = Ged2site::Display::locations->new($args);
		} elsif($page eq 'orphans') {
			$display = Ged2site::Display::orphans->new($args);
		} elsif($page eq 'ww1') {
			$display = Ged2site::Display::ww1->new($args);
		} elsif($page eq 'ww2') {
			$display = Ged2site::Display::ww2->new($args);
		} elsif($page eq 'military') {
			$display = Ged2site::Display::military->new($args);
		} elsif($page eq 'twins') {
			$display = Ged2site::Display::twins->new($args);
		} elsif($page eq 'reports') {
			$display = Ged2site::Display::reports->new($args);
		} elsif($page eq 'facts') {
			$display = Ged2site::Display::facts->new($args);
		} elsif($page eq 'mailto') {
			$display = Ged2site::Display::mailto->new($args);
		} elsif($page eq 'home') {
			$display = Ged2site::Display::home->new($args);
		} elsif($page eq 'meta-data') {
			$display = Ged2site::Display::meta_data->new($args);
		} else {
			$logger->info("Unknown page $page");
			$invalidpage = 1;
		}
	};

	my $error = $@;
	if($error) {
		$logger->error($error);
		$display = undef;
	}

	if(defined($display)) {
		# Pass in handles to the databases
		print $display->as_string({
			cachedir => $cachedir,
			people => $people,
			censuses => $censuses,
			changes => $changes,
			locations => $locations,
			orphans => $orphans,
			surnames => $surnames,
			history => $history,
			intermarriages => $intermarriages,
			todo => $todo,
			name_date => $name_date,
			surname_date => $surname_date,
			twins => $twins,
			military => $military,
			databasedir => $database_dir
		});
	} elsif($invalidpage) {
		choose();
		return;
	} else {
		$logger->debug('disabling cache');
		$fb->init(
			cache => undef,
		);
		if($error eq 'Unknown page to display') {
			print "Status: 400 Bad Request\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "I don't know what you want me to display.\n";
			}
		} elsif($error =~ /Can\'t locate .* in \@INC/) {
			$logger->error($error);
			print "Status: 500 Internal Server Error\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Software error - contact the webmaster\n",
					"$error\n";
			}
		} else {
			# No permission to show this page
			print "Status: 403 Forbidden\n",
				"Content-type: text/plain\n",
				"Pragma: no-cache\n\n";

			unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
				print "Access Denied\n";
			}
		}
		throw Error::Simple($error ? $error : $info->as_string());
	}
}

sub choose
{
	$logger->info('Called with no page to display');

	my $status = $info->status();

	if($status != 200) {
		require HTTP::Status;
		HTTP::Status->import();

		print "Status: $status ",
			HTTP::Status::status_message($status),
			"\n\n";
		return;
	}

	print "Status: 300 Multiple Choices\n",
		"Content-type: text/plain\n";

	my $path = $info->script_path();
	if(defined($path)) {
		my @statb = stat($path);
		my $mtime = $statb[9];
		print "Last-Modified: ", HTTP::Date::time2str($mtime), "\n";
	}

	print "\n";

	unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		print "/cgi-bin/page.fcgi?page=people\n",
			"/cgi-bin/page.fcgi?page=home\n",
			"/cgi-bin/page.fcgi?page=censuses\n",
			"/cgi-bin/page.fcgi?page=changes\n",
			"/cgi-bin/page.fcgi?page=surnames\n",
			"/cgi-bin/page.fcgi?page=history\n",
			"/cgi-bin/page.fcgi?page=todo\n",
			"/cgi-bin/page.fcgi?page=calendar\n",
			"/cgi-bin/page.fcgi?page=descendants\n",
			"/cgi-bin/page.fcgi?page=graphs\n",
			"/cgi-bin/page.fcgi?page=emmigrants\n",
			"/cgi-bin/page.fcgi?page=intermarriages\n",
			"/cgi-bin/page.fcgi?page=ww1\n",
			"/cgi-bin/page.fcgi?page=ww2\n",
			"/cgi-bin/page.fcgi?page=military\n",
			"/cgi-bin/page.fcgi?page=orphans\n",
			"/cgi-bin/page.fcgi?page=twins\n",
			"/cgi-bin/page.fcgi?page=reports\n",
			"/cgi-bin/page.fcgi?page=facts\n",
			"/cgi-bin/page.fcgi?page=mailto\n",
			"/cgi-bin/page.fcgi?page=meta-data\n";
	}
}

# False positives we don't need in the logs
sub filter {
	return 0 if($_[0] =~ /Can't locate Net\/OAuth\/V1_0A\/ProtectedResourceRequest.pm in /);
	return 0 if($_[0] =~ /Can't locate auto\/NetAddr\/IP\/InetBase\/AF_INET6.al in /);
	return 0 if($_[0] =~ /S_IFFIFO is not a valid Fcntl macro at /);

	return 1;
}
