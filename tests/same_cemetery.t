#!/usr/bin/env perl

# Regression test for noting that a person is buried or cremated in the same
#	cemetery as a close relative, e.g. "the same place as his wife, Mary Jones,
#	who was also buried there"
#
# Also covers bugs fixed at the same time:
#
#   Cremation dropped from the biography:
#	 When the date or place of death was known, place() was only given the
#	 burial place, so a cremation was silently omitted.
#
#   Cremation place printed twice:
#	 Once reachable, the cremation branch appended the place twice
#	 ("cremated in X in X").
#
use strict;
use warnings;
use Test::More;
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

# Family tree:
#
#	William Smith (I3, cremated at St Peter's)
#	|-- John Smith (I1, St Peter's) = Mary Jones (I2, St Peter's)
#	|	`-- Henry Smith (I4, Margate Cemetery)
#	`-- Ann Smith (I5, St Peter's)
#		`-- Tom Brown (I6, St Peter's)
#
#	Fred Green (I7) = Edith Green (I8): both buried in "Ramsgate, Kent, England",
#		a town rather than a cemetery, so must not be matched
#	Albert White (I9) = Alice White (I10): same town, but with the same ADDR,
#		so they are in the same cemetery
my ($fh, $gedfile) = tempfile(SUFFIX => '.ged', UNLINK => 1);
print $fh <<'END';
0 HEAD
1 SOUR ged2site
1 GEDC
2 VERS 5.5
1 CHAR UTF-8
0 @I1@ INDI
1 NAME John /Smith/
1 SEX M
1 BIRT
2 DATE 1 JAN 1850
2 PLAC Ramsgate, Kent, England
1 DEAT
2 DATE 3 MAR 1920
2 PLAC Margate, Kent, England
1 BURI
2 DATE 8 MAR 1920
2 PLAC St Peter's Churchyard, Broadstairs, Kent, England
1 FAMS @F1@
1 FAMC @F0@
0 @I2@ INDI
1 NAME Mary /Jones/
1 SEX F
1 BIRT
2 DATE 1 FEB 1852
1 DEAT
2 DATE 5 JUN 1925
2 PLAC Margate, Kent, England
1 BURI
2 DATE 9 JUN 1925
2 PLAC St Peter's Churchyard, Broadstairs, Kent, England
1 FAMS @F1@
0 @I3@ INDI
1 NAME William /Smith/
1 SEX M
1 BIRT
2 DATE 1 JAN 1820
1 DEAT
2 DATE 3 MAR 1890
1 CREM
2 DATE 8 MAR 1890
2 PLAC St Peter's Churchyard, Broadstairs, Kent, England
1 FAMS @F0@
0 @I4@ INDI
1 NAME Henry /Smith/
1 SEX M
1 BIRT
2 DATE 1 JAN 1880
1 DEAT
2 DATE 3 MAR 1940
1 BURI
2 PLAC Margate Cemetery, Margate, Kent, England
1 FAMC @F1@
0 @I5@ INDI
1 NAME Ann /Smith/
1 SEX F
1 DEAT
2 DATE 1 JAN 1930
1 BURI
2 PLAC St Peter's Churchyard, Broadstairs, Kent, England
1 FAMC @F0@
1 FAMS @F2@
0 @I6@ INDI
1 NAME Tom /Brown/
1 SEX M
1 DEAT
2 DATE 1 JAN 1950
1 BURI
2 PLAC St Peter's Churchyard, Broadstairs, Kent, England
1 FAMC @F2@
0 @I7@ INDI
1 NAME Fred /Green/
1 SEX M
1 DEAT
2 DATE 1 JAN 1931
1 BURI
2 PLAC Ramsgate, Kent, England
1 FAMS @F3@
0 @I8@ INDI
1 NAME Edith /Green/
1 SEX F
1 DEAT
2 DATE 1 JAN 1932
1 BURI
2 PLAC Ramsgate, Kent, England
1 FAMS @F3@
0 @I9@ INDI
1 NAME Albert /White/
1 SEX M
1 DEAT
2 DATE 1 JAN 1933
1 BURI
2 PLAC Ramsgate, Kent, England
2 ADDR Ramsgate Cemetery, Cecilia Road
1 FAMS @F4@
0 @I10@ INDI
1 NAME Alice /White/
1 SEX F
1 DEAT
2 DATE 1 JAN 1934
1 BURI
2 PLAC Ramsgate, Kent, England
2 ADDR Ramsgate Cemetery, Cecilia Road
1 FAMS @F4@
0 @F0@ FAM
1 HUSB @I3@
1 CHIL @I1@
1 CHIL @I5@
0 @F1@ FAM
1 HUSB @I1@
1 WIFE @I2@
1 MARR
2 DATE 1 JUN 1878
1 CHIL @I4@
0 @F2@ FAM
1 WIFE @I5@
1 CHIL @I6@
0 @F3@ FAM
1 HUSB @I7@
1 WIFE @I8@
0 @F4@ FAM
1 HUSB @I9@
1 WIFE @I10@
0 TRLR
END
close $fh;

run [$ged2site, '-h', 'John Smith', $gedfile],
	'>', \my $stdout, '2>', \my $stderr;

# Return the text of a person's static page, with the markup removed so that
#	links to relatives don't get in the way of matching the prose
sub bio
{
	my $xref = shift;

	my $file = "static-site/$xref.html";
	open(my $in, '<', $file) or return;
	local $/;
	my $html = <$in>;
	close $in;

	$html =~ s/<[^>]+>//g;
	$html =~ s/&apos;|&#39;/'/g;
	$html =~ s/\s+/ /g;
	return $html;
}

my %bio = map { $_ => bio($_) } qw(I1 I2 I3 I4 I5 I6 I7 I8 I9 I10);

foreach my $xref(sort keys %bio) {
	ok(defined($bio{$xref}), "static-site/$xref.html was generated");
}

SKIP: {
	skip 'Pages were not generated - cannot test biographies', 12
		if(grep { !defined } values %bio);

	# One relative, buried
	like($bio{'I2'}, qr/the same place as her husband, John Smith, who was also buried there/,
		'Single spouse in the same cemetery');

	# Several relatives, mixing burial and cremation
	like($bio{'I1'}, qr/the same place as his wife, Mary Jones; his father, William Smith; and his sister, Ann Smith, who were also laid to rest there/,
		'Several relatives, nearest first, mixing burial and cremation');

	# Two relatives: commas rather than semicolons
	like($bio{'I3'}, qr/the same place as his son, John Smith, and his daughter, Ann Smith, who were also buried there/,
		'Two relatives separated by a comma');

	# Grandparents and aunts/uncles
	like($bio{'I6'}, qr/his grandfather, William Smith/, 'Grandparent in the same cemetery');
	like($bio{'I6'}, qr/his uncle, John Smith/, 'Uncle in the same cemetery');
	like($bio{'I5'}, qr/her son, Tom Brown/, 'Child in the same cemetery');

	# A different cemetery
	unlike($bio{'I4'}, qr/the same place as/, 'No clause when buried in a different cemetery');

	# A town isn't a cemetery
	unlike($bio{'I7'}, qr/the same place as/, 'No clause when only the town is known');
	unlike($bio{'I8'}, qr/the same place as/, 'No clause when only the town is known (spouse)');

	# The ADDR identifies the cemetery
	like($bio{'I10'}, qr/the same place as her husband, Albert White, who was also buried there/,
		'Same ADDR in the same town is the same cemetery');

	# Cremation is described when the death is known, with the place only once
	like($bio{'I3'}, qr/was cremated in St Peter's Churchyard/, 'Cremation is in the biography');
	# An exact match, since "not repeated" checks would pass when the cremation is missing
	like($bio{'I3'}, qr/was cremated in St Peter's Churchyard, Broadstairs, Kent, England on Mar 8, 1890,/,
		'Cremation place given once, with a single space before the date');
}

# The dynamic site links to relatives through page.fcgi
SKIP: {
	open(my $csv, '<', 'dynamic-site/data/people.csv') or skip('people.csv was not generated', 1);
	my ($row) = grep { /^I2!/ } <$csv>;
	close $csv;

	like($row // '', qr/the same place as her husband, <a href="\?page=people&(amp;)?entry=I1">John Smith<\/a>, who was also buried there/,
		'Dynamic site biography links to the relative');
}

done_testing();
