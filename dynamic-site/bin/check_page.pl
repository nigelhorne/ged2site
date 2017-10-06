#!/usr/bin/env perl

use strict;
use warnings;

no lib '.';

use Test::More;
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

$t->do_compression_test(1);

$options{'REQUEST_METHOD'} = 'GET';
$options{'QUERY_STRING'} = 'page=people&home=1';
$t->run(\%options);
# diag($options{'body'});

$options{'QUERY_STRING'} = 'page=mailto';
$t->run(\%options);

$options{'QUERY_STRING'} = 'page=mailto&lang=en';
$t->run(\%options);
# diag($options{'body'});

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'en';
$options{'QUERY_STRING'} = 'page=mailto&lang=en';
diag($options{'body'});

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$options{'QUERY_STRING'} = 'page=people&home=1&lang=fr';
$t->run(\%options);

done_testing();
