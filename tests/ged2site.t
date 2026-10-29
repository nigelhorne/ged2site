#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 4;
use FindBin;
use File::Temp qw(tempfile tempdir);
use IPC::Run qw(run);

# Run ged2site in a directory of our own.  ged2site removes and recreates
#	static-site/ and dynamic-site/data in the current directory, so running in
#	the repo would destroy a real generated site, and with HARNESS_OPTIONS=j<n>
#	the tests would destroy each other's output
my $ged2site = "$FindBin::Bin/../ged2site";
my $workdir = tempdir(CLEANUP => 1);
mkdir("$workdir/dynamic-site") or BAIL_OUT("$workdir/dynamic-site: $!");
chdir($workdir) or BAIL_OUT("$workdir: $!");

# Leave the work directory so that it can be removed
END { chdir('/') }

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

my @cmd = ($ged2site, '-cFdh', 'John Doe', $filename);
my $output;
run \@cmd, '>', \$output;

# like($output, qr/Creating family tree website/, 'Output contains expected text');
ok(-d 'static-site', 'Static site directory exists');
ok(-d 'dynamic-site', 'Dynamic site directory exists');
ok(-f 'static-site/index.html', 'Static site index.html exists');
ok(-f 'dynamic-site/data/people.csv', 'Dynamic site people.csv exists');

unlink $filename;
