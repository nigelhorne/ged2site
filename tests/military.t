#!/usr/bin/env perl

# Tests for the dynamic site's military page, Ged2site::Display::military:
#
#   Someone with more than one military record must be listed once.
#   A record of someone who isn't in people.csv must be left out, not listed
#	with no name.
#   Names must be sorted as text, not as HTML: "&Eacute;mile" goes with the Es.
#   A tree with no military records has no military.csv, and the page must say
#	that no one has a record instead of dying.
#   Only the person and title are given to the template, not the whole of
#	their people.csv row.
#   Languages other than English must find a template.
#
# The databases are made in a tempdir, so no generated site is needed

use strict;
use warnings;
use Errno qw(ENOENT);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $root = "$FindBin::Bin/..";

BEGIN {
	plan(skip_all => 'The dynamic site needs modules that are not installed')
		unless(eval {
			unshift @INC, "$FindBin::Bin/../dynamic-site/lib";
			require Ged2site::Display::military;
			require Ged2site::DB::military;
			require Ged2site::DB::people;
			1
		});
}

# Write a !-separated CSV file of the given rows
sub write_csv
{
	my ($dir, $table, @rows) = @_;

	open(my $out, '>', File::Spec->catfile($dir, "$table.csv")) or BAIL_OUT("$table: $!");
	print $out join('!', @{$_}), "\n" foreach(@rows);
	close $out;
}

# Make the databases in a new directory, leaving out military.csv when there
#	are no military rows.  A new directory each time since
#	Database::Abstraction remembers what it has read
sub databases
{
	my @military = @_;

	my $dir = tempdir(CLEANUP => 1);
	write_csv($dir, 'people',
		[ 'entry', 'title', 'notes', 'bio' ],
		[ 'I1', 'Zoe Adams 1890 - 1970', 'person note', 'A long biography' ],
		[ 'I2', '&Eacute;mile Dupont 1895 - 1960', '', '' ],
		[ 'I3', 'adam Smith 1880 - 1950', '', '' ],
		[ 'I4', 'Edward Brown 1892 - 1918', '', '' ],
	);
	write_csv($dir, 'military', [ 'entry', 'person', 'date', 'place', 'notes' ], @military) if(scalar(@military));

	Database::Abstraction::init({ directory => $dir });
	return (Ged2site::DB::military->new(), Ged2site::DB::people->new());
}

my @records = (
	[ 1, 'I1', '1915', 'France', 'Army' ],
	[ 2, 'I2', '1916', 'Verdun', 'Infantry' ],
	[ 3, 'I1', '1940', 'England', 'Home Guard' ],	# a second record for I1
	[ 4, 'I3', '1900', 'South Africa', '' ],
	[ 5, 'I99', '1917', 'Belgium', 'Not in people.csv' ],
	[ 6, 'I4', '1918', 'France', '' ],
);

subtest '_people_with_records' => sub {
	my $found = Ged2site::Display::military::_people_with_records(databases(@records));

	is(ref($found), 'ARRAY', 'returns an arrayref');
	is_deeply(
		[ map { $_->{'person'} } @{$found} ],
		[ 'I3', 'I4', 'I2', 'I1' ],
		'listed once each, sorted by name ignoring case and accents, without people not in people.csv'
	);
	is_deeply([ sort keys %{$found->[0]} ], [ 'person', 'title' ], 'only person and title are kept');
	is($found->[2]->{'title'}, '&Eacute;mile Dupont 1895 - 1960', 'the title is still HTML');
};

subtest 'no military.csv' => sub {
	# The message is made by Database::Abstraction, not the OS, but check that
	#	the locale can't stop it being recognised
	local $! = ENOENT;
	my $enoent = "$!";
	foreach my $locale('en_US.UTF-8', 'de_DE.UTF-8', 'zh_CN.UTF-8') {
		local $ENV{'LC_ALL'} = $locale;
		my $found = eval { Ged2site::Display::military::_people_with_records(databases()) };
		is_deeply($found, [], "$locale: no records, rather than dying") or diag($@);
		unlike($@, qr/\Q$enoent\E/, "$locale: no OS error leaks out");
	}
};

subtest 'military.csv with no records' => sub {
	# ged2site doesn't write this, but an empty list must not reach the query
	my ($military, $people) = databases([ 'entry', 'person', 'date', 'place', 'notes' ]);
	my $found = eval { Ged2site::Display::military::_people_with_records($military, $people) };
	is_deeply($found, [], 'no one is listed') or diag($@);
};

subtest 'html' => sub {
	# Capture what would be given to the template, without needing a site config
	my @given;
	no warnings 'redefine';
	local *Web::VWF::Display::html = sub { shift; push @given, [ @_ ]; return 'html' };
	use warnings 'redefine';

	my $display = bless({}, 'Ged2site::Display::military');

	my ($military, $people) = databases(@records);
	is($display->html({ military => $military, people => $people }), 'html', 'returns the HTML');
	is(scalar(@{$given[-1]->[0]->{'military'}}), 4, 'the template is given the people');
	ok(exists($given[-1]->[0]->{'updated'}), 'and when they were updated');

	is($display->html(military => $military, people => $people), 'html', 'arguments can be a hash');

	$display->html({ military => (databases())[0], people => $people });
	is_deeply($given[-1], [], 'no military.csv: the template is given nothing');

	$display->html({ people => $people });
	is_deeply($given[-1], [], 'no military database: the template is given nothing');

	eval { $display->html({ military => $military }) };
	like($@, qr/'people' database not given/, 'croaks without the people database');
};

subtest 'templates' => sub {
	my $default = "$root/dynamic-site/templates/default/web/Ged2site/Display/military.tmpl";
	ok(-r $default, 'languages without a military template fall back to one');
};

done_testing();
