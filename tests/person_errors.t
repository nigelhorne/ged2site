#!/usr/bin/env perl

# GitHub issue #113: on a large tree, a run that died at the first person
#	whose data it couldn't handle meant waiting 20 minutes per data error.
#
#   A person whose page dies is reported, with their xref, and skipped.
#	Everyone else is still printed, and the run fails at the end with a
#	list of everyone who couldn't be printed.
#   The failed person's half-written rows are left out of the files shared by
#	everyone (people.csv, people.xml), rather than corrupting them.
#   -p xref,... only prints those people, to debug them quickly.
#
# No GEDCOM data reliably makes print_person() die, so a module given with -M
#	wraps it: it runs the real print_person(), so the person's rows are
#	written, and then dies for the xref in $ENV{GED2SITE_TEST_DIE}

use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempfile tempdir);
use FindBin;
use IPC::Run qw(run);
use Test::More;

my $ged2site = "$FindBin::Bin/../ged2site";

# Leave the work directories so that they can be removed
END { chdir('/') }

# A module that makes print_person() die for one person.  INIT runs after
#	ged2site has been compiled, so print_person() exists to be wrapped
my $libdir = tempdir(CLEANUP => 1);
open(my $pm, '>', File::Spec->catfile($libdir, 'DieOnPerson.pm')) or BAIL_OUT("DieOnPerson.pm: $!");
print $pm <<'END';
package DieOnPerson;
use strict;
use warnings;
INIT {
	no strict 'refs';
	no warnings 'redefine';
	my $real = \&main::print_person;
	*main::print_person = sub {
		my $person = $_[0]->{'person'};
		$real->(@_);
		die "Test failure for ", $person->xref(), "\n"
			if($person->xref() eq ($ENV{'GED2SITE_TEST_DIE'} // ''));
	};
}
1;
END
close($pm);

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
1 DEAT
2 DATE 3 MAR 1920
1 FAMS @F1@
0 @I2@ INDI
1 NAME Mary /Jones/
1 SEX F
1 BIRT
2 DATE 1 FEB 1852
1 DEAT
2 DATE 5 JUN 1925
1 FAMS @F1@
0 @I3@ INDI
1 NAME Henry /Smith/
1 SEX M
1 BIRT
2 DATE 1 JAN 1880
1 DEAT
2 DATE 3 MAR 1940
1 FAMC @F1@
0 @F1@ FAM
1 HUSB @I1@
1 WIFE @I2@
1 CHIL @I3@
1 MARR
2 DATE 1 JUN 1875
0 TRLR
END
close($fh);

# Run ged2site in a new directory of its own, since it removes and recreates
#	static-site/ and dynamic-site/data in the current directory
sub ged2site
{
	my %args = @_;

	my $workdir = tempdir(CLEANUP => 1);
	mkdir("$workdir/dynamic-site") or BAIL_OUT("$workdir/dynamic-site: $!");
	chdir($workdir) or BAIL_OUT("$workdir: $!");

	local $ENV{'GED2SITE_TEST_DIE'} = $args{'die_for'} // '';
	my ($out, $err);
	run([ $^X, "-I$libdir", '-MDieOnPerson', $ged2site, @{$args{'options'} // []}, '-h', 'John Smith', $gedfile ],
		\undef, \$out, \$err);

	return { status => $? >> 8, stderr => $err, dir => $workdir };
}

# The xrefs in people.csv, checking that each row has every column
sub people_csv
{
	my $dir = shift;

	open(my $in, '<', "$dir/dynamic-site/data/people.csv") or return;
	my @lines = grep { length } map { s/\R$//r } <$in>;
	close($in);

	my $header = shift @lines;
	my $columns = scalar(split(/!/, $header, -1));
	my @bad = grep { scalar(split(/!/, $_, -1)) != $columns } @lines;
	return { xrefs => [ sort map { (split(/!/))[0] } @lines ], bad => \@bad };
}

subtest 'a person whose page dies' => sub {
	my $run = ged2site(die_for => 'I2');

	is($run->{'status'}, 1, 'the run fails');
	like($run->{'stderr'}, qr/I2 \(Mary Jones[^)]*\): Test failure for I2/, 'the person is named, with the error');
	like($run->{'stderr'}, qr/1 person couldn't be printed, so the site is incomplete/, 'and listed at the end');

	ok(-r "$run->{dir}/static-site/I1.html", 'people before them are still printed');
	ok(-r "$run->{dir}/static-site/I3.html", 'and people after them');

	my $csv = people_csv($run->{'dir'});
	is_deeply($csv->{'xrefs'}, [ 'I1', 'I3' ], "people.csv doesn't have their row");
	is_deeply($csv->{'bad'}, [], 'and every row is complete');

	my $xml = do { local $/; open(my $in, '<', "$run->{dir}/dynamic-site/data/people.xml") or die; <$in> };
	is(() = $xml =~ /<person /g, 2, "people.xml doesn't have them either");
	is(() = $xml =~ /<person /g, () = $xml =~ m{</person>}g, 'and every person element is closed');
};

subtest '-f still stops at the first failure' => sub {
	# -f makes every warning fatal, and this tree has no places of birth, so
	#	the first person's warning stops the run, before I2 is reached
	my $run = ged2site(die_for => 'I2', options => [ '-f' ]);

	isnt($run->{'status'}, 0, 'the run fails');
	like($run->{'stderr'}, qr/John Smith: .* at line \d+/, "at the first person's warning");
	unlike($run->{'stderr'}, qr/couldn't be printed/, 'straight away, without carrying on');
	ok(!-e "$run->{dir}/static-site/I3.html", 'so no one after them is printed');
};

subtest 'no failures' => sub {
	my $run = ged2site();

	is($run->{'status'}, 0, 'the run succeeds');
	unlike($run->{'stderr'}, qr/couldn't be printed|incomplete/, 'with no failure report');
	is_deeply(people_csv($run->{'dir'})->{'xrefs'}, [ 'I1', 'I2', 'I3' ], 'everyone is printed');
};

subtest '-p' => sub {
	my $run = ged2site(options => [ '-p', 'I3' ]);

	is($run->{'status'}, 0, 'the run succeeds');
	ok(-r "$run->{dir}/static-site/I3.html", 'the person asked for is printed');
	ok(!-e "$run->{dir}/static-site/I1.html", 'no one else is');
	is_deeply(people_csv($run->{'dir'})->{'xrefs'}, [ 'I3' ], 'people.csv only has them');
	like($run->{'stderr'}, qr/only some people were printed \(-p\), so the site is incomplete/, 'and it says the site is incomplete');

	$run = ged2site(options => [ '-p', 'I1, Henry Smith' ]);
	is_deeply(people_csv($run->{'dir'})->{'xrefs'}, [ 'I1', 'I3' ], 'people can be given by xref or name');

	$run = ged2site(options => [ '-p', 'I3' ], die_for => 'I3');
	is($run->{'status'}, 1, 'a failure is still reported');
	like($run->{'stderr'}, qr/I3 \(Henry Smith[^)]*\): Test failure for I3/, 'with the error');

	$run = ged2site(options => [ '-p', 'I99' ]);
	isnt($run->{'status'}, 0, 'someone not in the tree is an error');
	like($run->{'stderr'}, qr/Can't find 'I99'/, 'which says who');
};

done_testing();
