#!/usr/bin/env perl

use strict;
use warnings;

no lib '.';

use Gzip::Faster;
use Test::Most;
use Test::CGI::External; # https://metacpan.org/pod/release/BKB/Test-CGI-External-0.02/lib/Test/CGI/External.pod
use FindBin;
use autodie qw(:all);

$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
$ENV{'SERVER_PORT'} = 443;
$ENV{'NO_CACHE'} = 1;

my $t = Test::CGI::External->new();

$ENV{'REMOTE_ADDR'} = '212.159.106.41';	# Send the logging to a file not stdout

# $t->set_cgi_executable("$FindBin::Bin/bb-links.fcgi", '--mobile');
$t->set_cgi_executable("$FindBin::Bin/../cgi-bin/page.fcgi");

my %options;

diag('Basic sanity tests');
$t->set_verbosity(1);

diag('Test no arguments');
$t->run(\%options);

# Don't do these tests earlier, since the 300 response won't be compressed or cached
$t->do_compression_test(1);
$t->do_caching_test(1);

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'en';
$options{'REQUEST_METHOD'} = 'GET';
$options{'QUERY_STRING'} = 'page=people&home=1';
$t->run(\%options);
# diag($options{'body'});

$options{'QUERY_STRING'} = 'page=mailto';
$t->run(\%options);
# diag($options{'body'});

$options{'QUERY_STRING'} = 'page=mailto&lang=en';
$t->run(\%options);

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$options{'QUERY_STRING'} = 'page=mailto&lang=fr';
$t->run(\%options);
# diag($options{'body'});

diag('test not implemented');
$t->test_not_implemented();

diag('test not allowed');
$t->test_method_not_allowed('DELETE');

diag('test HTTP 411');
$t->test_411();

diag('Finishing');
done_testing();
