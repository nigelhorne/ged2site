#!/usr/bin/env perl

use strict;
use warnings;

no lib '.';

use Test::Tester;
use Test::More;
use Test::CGI::External; # https://metacpan.org/pod/release/BKB/Test-CGI-External-0.02/lib/Test/CGI/External.pod
use FindBin;
use autodie qw(:all);

$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
$ENV{'SERVER_PORT'} = 443;

my $t = Test::CGI::External->new();

$ENV{'REMOTE_ADDR'} = '212.159.106.41';	# Send the logging to a file not stdout

# $t->set_cgi_executable("$FindBin::Bin/bb-links.fcgi", '--mobile');
$t->set_cgi_executable("$FindBin::Bin/../cgi-bin/page.fcgi");

my %options;

# $options{'QUERY_STRING'} = 'address=njh@bandsman.co.uk&redir=www.google.com';
# $options{no_check_content} = 1;	# It'll just set a location header
# $t->set_no_check_content(1);

my ($premature, @results) = run_tests(
	sub {
		$t->do_compression_test(1);

		$options{'REQUEST_METHOD'} = 'GET';
		$options{'QUERY_STRING'} = 'page=people&home=1';
		$t->run(\%options);
	}
);

# diag $options{'header'};
# diag $options{'body'};

ok (!$premature, 'no premature diagnostics');
foreach my $result(@results) {
	ok($result->{'ok'}, "passed $result->{name}");
}

done_testing();
