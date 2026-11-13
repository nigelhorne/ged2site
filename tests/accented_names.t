#!/usr/bin/env perl

# Regression test: names starting with an accented capital lost the capital
#	in biographies, e.g. "<b>&eacute;mile</b>" for Émile.  The name was made
#	into HTML entities and then lowercased, which lowercased the entity too
#	("&Eacute;" -> "&eacute;").  The case must be changed first, on
#	characters rather than UTF-8 bytes.

use strict;
use warnings;
use File::Temp qw(tempfile tempdir);
use FindBin;
use IPC::Run qw(run);
use Test::More;

# Run ged2site in a directory of our own, since it removes and recreates
#	static-site/ and dynamic-site/data in the current directory
my $ged2site = "$FindBin::Bin/../ged2site";
my $workdir = tempdir(CLEANUP => 1);
mkdir("$workdir/dynamic-site") or BAIL_OUT("$workdir/dynamic-site: $!");
chdir($workdir) or BAIL_OUT("$workdir: $!");

# Leave the work directory so that it can be removed
END { chdir('/') }

# Émile Öberg's surname and given name both start with an accented capital,
#	as does Élodie's given name.  Zoë Müller has accents after the
#	first letter, which must not be corrupted by changing the case of UTF-8
#	bytes ("Zoã")
my ($fh, $gedfile) = tempfile(SUFFIX => '.ged', UNLINK => 1);
print $fh <<'END';
0 HEAD
1 SOUR ged2site
1 GEDC
2 VERS 5.5
1 CHAR UTF-8
0 @I1@ INDI
1 NAME Émile /Öberg/
1 SEX M
1 BIRT
2 DATE 1 JAN 1850
2 PLAC Besançon, Doubs, France
1 DEAT
2 DATE 3 MAR 1920
2 PLAC Zürich, Switzerland
1 FAMS @F1@
0 @I2@ INDI
1 NAME Élodie /Dupont/
1 SEX F
1 BIRT
2 DATE 1 FEB 1852
2 PLAC Besançon, Doubs, France
1 DEAT
2 DATE 5 JUN 1925
2 PLAC Zürich, Switzerland
1 FAMS @F1@
0 @I3@ INDI
1 NAME Zoë /Müller/
1 SEX F
1 BIRT
2 DATE 1 JAN 1880
2 PLAC Besançon, Doubs, France
1 DEAT
2 DATE 1 JAN 1950
2 PLAC Zürich, Switzerland
0 @F1@ FAM
1 HUSB @I1@
1 WIFE @I2@
1 MARR
2 DATE 1 JUN 1875
0 TRLR
END
close($fh);

my ($out, $err);
run([ $^X, $ged2site, '-h', 'Émile Öberg', $gedfile ], \undef, \$out, \$err);
is($? >> 8, 0, 'ged2site runs') or diag($err);

# The biography is the text after the page's heading
foreach my $test([ 'I1', '&Eacute;mile', '&Ouml;berg' ], [ 'I2', '&Eacute;lodie' ], [ 'I3', 'Zo&euml;', 'M&uuml;ller' ]) {
	my ($xref, @names) = @{$test};

	open(my $in, '<', "static-site/$xref.html") or BAIL_OUT("static-site/$xref.html: $!");
	my $html = do { local $/; <$in> };
	close($in);
	my ($bio) = $html =~ m{</h1>(.*)}s;

	foreach my $name(@names) {
		like($bio, qr/\Q$name\E/, "$xref: the biography has $name");
		# e.g. "&eacute;mile", what the bug produced
		my $lowercased = lc($name);
		unlike($bio, qr/\Q$lowercased\E/, "$xref: and not $lowercased");
	}
}

# The dynamic site's biography too
open(my $csv, '<', 'dynamic-site/data/people.csv') or BAIL_OUT("people.csv: $!");
my $people = do { local $/; <$csv> };
close($csv);
unlike($people, qr/&eacute;mile|&eacute;lodie|&ouml;berg/, 'people.csv has no lowercased names');
like($people, qr/&Eacute;mile/, 'and has the capitalised one');

done_testing();
