#!/usr/bin/env perl

# Gedsite is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Based on VWF - https://github.com/nigelhorne/vwf

# use File::HomeDir;
# use lib File::HomeDir->my_home() . '/lib/perl5';

use strict;
use warnings;
# use diagnostics;

use Log::Log4perl qw(:levels);	# Put first to cleanup last
use CGI::Carp qw(fatalsToBrowser);
use CHI;
use CGI::Info;
use CGI::Lingua;
use File::Basename;
use FCGI;
use FCGI::Buffer;
use File::HomeDir;
use Log::Any::Adapter;
use Error::Simple;

# use lib '/usr/lib';	# This needs to point to the Gedsite directory lives,
			# i.e. the contents of the lib directory in the
			# distribution
use lib '../lib';

my $info = CGI::Info->new();
my $tmpdir = $info->tmpdir();
my $cachedir = "$tmpdir/cache";
my $script_dir = $info->script_dir();

my @suffixlist = ('.pl', '.fcgi');
my $script_name = basename($info->script_name(), @suffixlist);

# open STDERR, ">&STDOUT";
close STDERR;
open(STDERR, '>>', "$tmpdir/$script_name.stderr");

my $infocache = CHI->new(driver => 'Memcached', servers => [ '127.0.0.1:11211' ], namespace => 'CGI::Info');
my $linguacache = CHI->new(driver => 'Memcached', servers => [ '127.0.0.1:11211' ], namespace => 'CGI::Lingua');
# my $buffercache = CHI->new(driver => 'Redis', root_dir => $cachedir, namespace => $script_name);
my $buffercache = CHI->new(driver => 'File', root_dir => $cachedir, namespace => $script_name);

Log::Log4perl->init("$script_dir/../conf/$script_name.l4pconf");
my $logger = Log::Log4perl->get_logger($script_name);

# my $pagename = "Gedsite::Display::$script_name";
# eval "require $pagename";
use Gedsite::Display::people;
use Gedsite::Display::censuses;
use Gedsite::Display::surnames;

use Gedsite::DB::people;
use Gedsite::DB::censuses;
use Gedsite::DB::surnames;

my $database_dir = "$script_dir/../databases";
Gedsite::DB::init({ directory => $database_dir, logger => $logger });

my $people = Gedsite::DB::people->new();
if($@) {
	$logger->error($@);
	die $@;
}
my $censuses = Gedsite::DB::censuses->new();
my $surnames = Gedsite::DB::surnames->new();

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
	$requestcount++;
	if($ENV{'REMOTE_ADDR'}) {
		Log::Any::Adapter->set( { category => $script_name }, 'Log4perl');
	} else {
		Log::Any::Adapter->set('Stdout');
	}
	$logger = Log::Any->get_logger(category => $script_name);
	$logger->info("Request $requestcount", $ENV{'REMOTE_ADDR'} ? " $ENV{'REMOTE_ADDR'}" : '');

	$Error::Debug = 1;

	eval {
		doit();
	};
	if($@) {
		my $msg = $@;
		warn $msg unless(defined($ENV{'REMOTE_ADDR'}));
		$logger->error($msg);
	}
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
	my $info = CGI::Info->new({ cache => $infocache });

	if(!defined($info->param('page'))) {
		print "Location: /index.htm\n\n";
		$logger->info('Called with no page to display');
		return;
	}

	my $fb = FCGI::Buffer->new();
	$fb->init({ info => $info, optimise_content => 1, lint_content => 0, logger => $logger });
	if(!$ENV{'REMOTE_ADDR'}) {
		$fb->init(lint_content => 1);
	}
	if($fb->can_cache()) {
		$fb->init(
			cache => $buffercache,
			# generate_304 => 0,
		);
		if($fb->is_cached()) {
			return;
		}
	}

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
	};
	eval {
		if($info->param('page') eq 'people') {
			$display = Gedsite::Display::people->new($args);
		} elsif($info->param('page') eq 'censuses') {
			$display = Gedsite::Display::censuses->new($args);
		} elsif($info->param('page') eq 'surnames') {
			$display = Gedsite::Display::surnames->new($args);
		} else {
			$invalidpage = 1;
		}
	};

	my $error = $@;

	if(defined($display)) {
		# Pass in a handle to the database
		print $display->as_string({
			people => $people, censuses => $censuses, surnames => $surnames, cachedir => $cachedir
		});
	} elsif($invalidpage) {
		print "Status: 300 Multiple Choices\n",
			"Content-type: text/plain\n\n";
		unless($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
			print "/cgi-bin/page.fcgi?page=people\n",
				"/cgi-bin/page.fcgi?page=censuses\n",
				"/cgi-bin/page.fcgi?page=surnames\n",
		}
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
