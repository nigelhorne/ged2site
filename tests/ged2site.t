#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 4;
use File::Temp qw(tempfile);
use IPC::Run qw(run);

my ($fh, $filename) = tempfile();
print $fh <<'END';
0 HEAD
1 SOUR ged2site
1 GEDC
2 VERS 5.5
1 CHAR UTF-8
0 @I1@ INDI
1 NAME John /Doe/
1 SEX M
END
close $fh;

my @cmd = ('./ged2site', '-cFdh', 'John Doe', $filename);
my $output;
run \@cmd, '>', \$output;

# like($output, qr/Creating family tree website/, 'Output contains expected text');
ok(-d 'static-site', 'Static site directory exists');
ok(-d 'dynamic-site', 'Dynamic site directory exists');
ok(-f 'static-site/index.html', 'Static site index.html exists');
ok(-f 'dynamic-site/index.html', 'Dynamic site index.html exists');

unlink $filename;
