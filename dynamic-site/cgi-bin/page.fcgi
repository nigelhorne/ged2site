#!/usr/bin/env perl

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# use File::HomeDir;
# use lib File::HomeDir->my_home() . '/lib/perl5';

use strict;
use warnings;
# use diagnostics;

use Log::Log4perl qw(:levels);	# Put first to cleanup last
use CGI::Carp qw(fatalsToBrowser);
use CGI::Info;
use CGI::Lingua;
use File::Basename;
use FCGI;
use FCGI::Buffer;
use File::HomeDir;
use Log::Any::Adapter;
use Error qw(:try);
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

# my $pagename = "Ged2site::Display::$script_name";
# eval "require $pagename";
use Ged2site::Display::people;
use Ged2site::Display::censuses;
use Ged2site::Display::surnames;
use Ged2site::Display::history;
use Ged2site::Display::todo;
use Ged2site::Display::calendar;

use Ged2site::DB::people;
use Ged2site::DB::censuses;
use Ged2site::DB::surnames;
use Ged2site::DB::history;
use Ged2site::DB::todo;

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
		Log::Any::Adapter->set('Stdout');
		$logger = Log::Any->get_logger(category => $script_name);
		try {
			doit();
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

	$Error::Debug = 1;

	try {
		doit();
	} catch Error with {
		my $msg = shift;
		warn $msg;
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

sub doit
{
	CGI::Info->reset();
	$config ||= Ged2site::Config->new({ logger => $logger, info => $info });
	$infocache ||= create_memory_cache(config => $config, logger => $logger, namespace => 'CGI::Info');
	my $info = CGI::Info->new({ cache => $infocache, logger => $logger });

	if(!defined($info->param('page'))) {
		choose();
		return;
	}

	my $fb = FCGI::Buffer->new();
	$fb->init({ info => $info, optimise_content => 1, lint_content => 0, logger => $logger });
	if(!$ENV{'REMOTE_ADDR'}) {
		$fb->init(lint_content => 1);
	}
	if($fb->can_cache()) {
		$buffercache ||= create_disc_cache(config => $config, logger => $logger, namespace => $script_name, root_dir => $cachedir);
		$fb->init(
			cache => $buffercache,
			# generate_304 => 0,
		);
		if($fb->is_cached()) {
			return;
		}
	}

	$linguacache ||= create_memory_cache(config => $config, logger => $logger, namespace => 'CGI::Lingua');
	my $lingua = CGI::Lingua->new({
		supported => [ 'en-gb' ],
		cache => $linguacache,
		info => $info,
		logger => $logger,
	});

	my $display;
	my $invalidpage;
	my $args = {
		info => $info,
		logger => $logger,
		lingua => $lingua,
		config => $config,
	};
	eval {
		if($info->param('page') eq 'people') {
			$display = Ged2site::Display::people->new($args);
		} elsif($info->param('page') eq 'censuses') {
			$display = Ged2site::Display::censuses->new($args);
		} elsif($info->param('page') eq 'surnames') {
			$display = Ged2site::Display::surnames->new($args);
		} elsif($info->param('page') eq 'history') {
			$display = Ged2site::Display::history->new($args);
		} elsif($info->param('page') eq 'todo') {
			$display = Ged2site::Display::todo->new($args);
		} elsif($info->param('page') eq 'calendar') {
			$display = Ged2site::Display::calendar->new($args);
		} else {
			$invalidpage = 1;
		}
	};

	my $error = $@;

	if(defined($display)) {
		# Pass in handles to the databases
		print $display->as_string({
			people => $people,
			censuses => $censuses,
			surnames => $surnames,
			history => $history,
			todo => $todo,
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

	print "Status: 300 Multiple Choices\n",
		"Content-type: text/plain\n\n";

	unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		print "/cgi-bin/page.fcgi?page=people\n",
			"/cgi-bin/page.fcgi?page=censuses\n",
			"/cgi-bin/page.fcgi?page=surnames\n",
			"/cgi-bin/page.fcgi?page=history\n",
			"/cgi-bin/page.fcgi?page=todo\n",
			"/cgi-bin/page.fcgi?page=calendar\n",
	}
}
