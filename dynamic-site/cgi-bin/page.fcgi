#!/usr/bin/env perl

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# use File::HomeDir;
# use lib File::HomeDir->my_home() . '/lib/perl5';

use strict;
use warnings;
# use diagnostics;

no lib '.';

use Log::Log4perl qw(:levels);	# Put first to cleanup last
use CGI::Carp qw(fatalsToBrowser);
use CGI::Info;
use CGI::Lingua;
use File::Basename;
# use CGI::Alert 'you@example.com';
use FCGI;
use FCGI::Buffer;
use File::HomeDir;
use Log::Any::Adapter;
use Error qw(:try);
use File::Spec;
use Log::WarnDie 0.09;
use autodie qw(:all);

# use lib '/usr/lib';	# This needs to point to the Ged2site directory lives,
			# i.e. the contents of the lib directory in the
			# distribution
use lib '../lib';

use Ged2site::Config;

my $info = CGI::Info->new();
my $tmpdir = $info->tmpdir();
my $cachedir = "$tmpdir/cache";
my $script_dir = $info->script_dir();
my $config;

my @suffixlist = ('.pl', '.fcgi');
my $script_name = basename($info->script_name(), @suffixlist);

my $infocache;
my $linguacache;
my $buffercache;

Log::Log4perl->init("$script_dir/../conf/$script_name.l4pconf");
my $logger = Log::Log4perl->get_logger($script_name);
Log::WarnDie->dispatcher($logger);

# my $pagename = "Ged2site::Display::$script_name";
# eval "require $pagename";
use Ged2site::Display::people;
use Ged2site::Display::censuses;
use Ged2site::Display::surnames;
use Ged2site::Display::history;
use Ged2site::Display::todo;
use Ged2site::Display::calendar;
use Ged2site::Display::descendants;
use Ged2site::Display::graphs;
use Ged2site::Display::emmigrants;
use Ged2site::Display::ww1;
use Ged2site::Display::twins;
use Ged2site::Display::reports;
use Ged2site::Display::mailto;

use Ged2site::DB::people;
if($@) {
	$logger->error($@);
	die $@;
}
use Ged2site::DB::censuses;
use Ged2site::DB::surnames;
use Ged2site::DB::history;
use Ged2site::DB::todo;
use Ged2site::DB::names;

my $database_dir = "$script_dir/../databases";
Ged2site::DB::init({ directory => $database_dir, logger => $logger });

my $people = Ged2site::DB::people->new();
if($@) {
	$logger->error($@);
	die $@;
}
my $censuses = Ged2site::DB::censuses->new();
my $surnames = Ged2site::DB::surnames->new();
my $history = Ged2site::DB::history->new();
my $todo = Ged2site::DB::todo->new();
my $names = Ged2site::DB::names->new();

# open STDERR, ">&STDOUT";
close STDERR;
open(STDERR, '>>', "$tmpdir/$script_name.stderr");

# http://www.fastcgi.com/docs/faq.html#PerlSignals
my $requestcount = 0;
my $handling_request = 0;
my $exit_requested = 0;

sub sig_handler {
	$exit_requested = 1;
	$logger->trace('In sig_handler');
	if(!$handling_request) {
		$logger->info('Shutting down');
		if($buffercache) {
			$buffercache->purge();
		}
		CHI->stats->flush();
		exit(0);
	}
}

$SIG{USR1} = \&sig_handler;
$SIG{TERM} = \&sig_handler;
$SIG{PIPE} = 'IGNORE';

my $request = FCGI::Request();

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
		$names->set_logger($logger);
		$info->set_logger($logger);
		$Error::Debug = 1;
		try {
			doit(debug => 1);
		} catch Error with {
			my $msg = shift;
			warn "$msg\n", $msg->stacktrace;
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

	try {
		doit(debug => 0);
	} catch Error with {
		my $msg = shift;
		$logger->error($msg);
		if($buffercache) {
			$buffercache->clear();
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
exit(0);

sub doit
{
	CGI::Info->reset();

	$logger->debug('In doit - domain is ', $info->domain_name());

	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
	$config ||= Ged2site::Config->new({ logger => $logger, info => $info });
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
		supported => [ 'en-gb' ],
		cache => $linguacache,
		info => $info,
		logger => $logger,
		debug => $args{'debug'},
		syslog => $syslog,
	});

	my $args = {
		info => $info,
		optimise_content => 1,
		lint_content => 0,
		logger => $logger,
		lingua => $lingua
	};
	if(!$ENV{'REMOTE_ADDR'}) {
		$args->{'lint_content'} = 1;
	}
	if(!$info->is_search_engine() && $config->rootdir() && ((!defined($info->param('action'))) || ($info->param('action') ne 'send'))) {
		$args->{'save_to'} = {
			directory => File::Spec->catfile($config->rootdir(), 'save_to'),
			ttl => 3600 * 24,
			create_table => 1
		};
	}

	my $fb = FCGI::Buffer->new();

	$fb->init($args);

	if($fb->can_cache()) {
		$buffercache ||= create_disc_cache(config => $config, logger => $logger, namespace => $script_name, root_dir => $cachedir);
		$fb->init(
			cache => $buffercache,
			# generate_304 => 0,
			cache_age => '1 day',
		);
		if($fb->is_cached()) {
			return;
		}
	}

	my $display;
	my $invalidpage;
	$args = {
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
		} elsif($page eq 'descendants') {
			$display = Ged2site::Display::descendants->new($args);
		} elsif($page eq 'graphs') {
			$display = Ged2site::Display::graphs->new($args);
		} elsif($page eq 'emmigrants') {
			$display = Ged2site::Display::emmigrants->new($args);
		} elsif($page eq 'ww1') {
			$display = Ged2site::Display::ww1->new($args);
		} elsif($page eq 'twins') {
			$display = Ged2site::Display::twins->new($args);
		} elsif($page eq 'reports') {
			$display = Ged2site::Display::reports->new($args);
		} elsif($page eq 'mailto') {
			$display = Ged2site::Display::mailto->new($args);
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
			people => $people,
			censuses => $censuses,
			surnames => $surnames,
			history => $history,
			todo => $todo,
			names => $names,
			cachedir => $cachedir
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
				print "There is a problem with your connection. Please contact your ISP.\n";
			}
		}
		throw Error::Simple($error ? $error : $info->as_string());
	}
}

sub choose
{
	$logger->info('Called with no page to display');

	return unless($info->status() == 200);

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
			"/cgi-bin/page.fcgi?page=censuses\n",
			"/cgi-bin/page.fcgi?page=surnames\n",
			"/cgi-bin/page.fcgi?page=history\n",
			"/cgi-bin/page.fcgi?page=todo\n",
			"/cgi-bin/page.fcgi?page=calendar\n",
			"/cgi-bin/page.fcgi?page=descendants\n",
			"/cgi-bin/page.fcgi?page=graphs\n",
			"/cgi-bin/page.fcgi?page=emmigrants\n",
			"/cgi-bin/page.fcgi?page=ww1\n",
			"/cgi-bin/page.fcgi?page=twins\n",
			"/cgi-bin/page.fcgi?page=reports\n",
			"/cgi-bin/page.fcgi?page=mailto\n";
	}
}
