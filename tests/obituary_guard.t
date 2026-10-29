#!/usr/bin/env perl

# Regression test: with -w, ged2site searches Genealogy::Obituary::Lookup and
#	Genealogy::Wills, whose search() croaks on arguments outside its schema,
#	aborting the whole run.  Seen with a woman whose husband has no surname
#	(her married name was ''), and possible with surnames such as "O'Brien",
#	non-ASCII names (which wide_to_html() turns into "&ouml;"), and impossible
#	ages from wrong dates

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

# Everyone dies in Kent, so that the wills database is searched too
my ($fh, $gedfile) = tempfile(SUFFIX => '.ged', UNLINK => 1);
binmode($fh, ':utf8');
print $fh <<"END";
0 HEAD
1 CHAR UTF-8
0 \@I1\@ INDI
1 NAME Fred
1 SEX M
1 FAMS \@F1\@
0 \@I2\@ INDI
1 NAME Edith /Green/
1 SEX F
1 BIRT
2 DATE 1 JAN 1880
1 DEAT
2 DATE 1 JAN 1950
2 PLAC Margate, Kent, England
1 FAMS \@F1\@
0 \@I3\@ INDI
1 NAME Zo\x{eb} /M\x{fc}ller/
1 SEX F
1 BIRT
2 DATE 1 JAN 1880
1 DEAT
2 DATE 1 JAN 1950
2 PLAC Margate, Kent, England
0 \@I4\@ INDI
1 NAME Sean /O'Brien/
1 SEX M
1 BIRT
2 DATE 1 JAN 1700
1 DEAT
2 DATE 1 JAN 1950
2 PLAC Margate, Kent, England
0 \@F1\@ FAM
1 HUSB \@I1\@
1 WIFE \@I2\@
0 TRLR
END
close $fh;

run [$ged2site, '-w', '-h', 'Edith Green', $gedfile],
	'>', \my $stdout, '2>', \my $stderr;
my $status = $? >> 8;

is($status, 0, 'ged2site -w completes');
unlike(($stdout // '') . ($stderr // ''), qr/validate_strict/, 'No search() argument validation errors');

ok(-f "static-site/$_.html", "static-site/$_.html was generated") foreach(qw(I2 I3 I4));

done_testing();
