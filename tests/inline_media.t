#!/usr/bin/env perl

# Regression test for inline media objects (an OBJE inside an INDI, so with no
#	xref) getting a different filename each time make_filename_from_object()
#	was called.  The static and dynamic copies of the image were saved under
#	different names, so pages could refer to a file that didn't exist.
#
# Also checks that the random prefix is only letters and digits: it used to
#	be able to contain "/", which made the name a path to a nonexistent directory

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempfile tempdir);
use IPC::Run qw(run);
use MIME::Base64 qw(decode_base64);

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

# A 4x4 red JPEG, so that the test doesn't need ImageMagick
my $jpeg = "$workdir/headstone.jpg";
open(my $img, '>:raw', $jpeg) or BAIL_OUT("$jpeg: $!");
print $img decode_base64(<<'END');
/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkz
ODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2Nj
Y2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAEAAQDASIA
AhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEB
AQAAAAAAAAAAAAAAAAAABQb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCKALXj
/9k=
END
close $img;

my ($fh, $gedfile) = tempfile(SUFFIX => '.ged', UNLINK => 1);
print $fh <<"END";
0 HEAD
1 SOUR ged2site
1 GEDC
2 VERS 5.5
1 CHAR UTF-8
0 \@I1\@ INDI
1 NAME John /Smith/
1 SEX M
1 DEAT
2 DATE 3 MAR 1920
1 OBJE
2 FILE $jpeg
2 FORM jpg
2 TITL Headstone
0 TRLR
END
close $fh;

run [$ged2site, '-d', '-h', 'John Smith', $gedfile],
	'>', \my $stdout, '2>', \my $stderr;

my @static = glob('static-site/img/*-Headstone.jpg');
my @dynamic = glob('dynamic-site/img/*-Headstone.jpg');

is(scalar(@static), 1, 'One copy of the image in the static site');
is(scalar(@dynamic), 1, 'One copy of the image in the dynamic site');

SKIP: {
	skip 'Images were not saved', 4 if((scalar(@static) != 1) || (scalar(@dynamic) != 1));

	my ($static) = $static[0] =~ m{([^/]+)$};
	my ($dynamic) = $dynamic[0] =~ m{([^/]+)$};

	is($dynamic, $static, 'Static and dynamic copies have the same name');
	like($static, qr/^[A-Za-z0-9]{6}-Headstone\.jpg$/, 'Random prefix is only letters and digits');

	open(my $in, '<', 'static-site/I1.html') or BAIL_OUT("static-site/I1.html: $!");
	my $html = do { local $/; <$in> };
	close $in;
	like($html, qr{img/\Q$static\E}, 'Static page refers to the saved image');

	open($in, '<', 'dynamic-site/data/people.csv') or BAIL_OUT("people.csv: $!");
	my ($row) = grep { /^I1!/ } <$in>;
	close $in;
	like($row // '', qr{img/\Q$static\E}, 'Dynamic site refers to the saved image');
}

done_testing();
