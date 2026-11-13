package Ged2site::Display::military;

# Display the Military Records page: an alphabetical list of everyone in the
#	tree who has at least one military record, each linking to their page

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak);
use Database::Join;
use HTML::Entities ();
use Params::Get;
use Readonly;
use Unicode::Collate;

use parent 'Web::VWF::Display';

our $VERSION = '0.01';

# military.csv refers to a person by this column, people.csv calls it 'entry'
Readonly::Scalar my $JOIN_COLUMN => 'person';
Readonly::Scalar my $PEOPLE_KEY => 'entry';

# Database::Abstraction's documented message when a table has no file.
#	ged2site only writes military.csv when someone has a military record,
#	so for many trees this is the normal case, not an error
Readonly::Scalar my $NO_TABLE => qr/^Can't find a file called /;

# Level 1 compares letters only, so neither accents nor case change the order
Readonly::Scalar my $COLLATION_LEVEL => 1;

# Made when first needed, then kept for the life of the FastCGI process,
#	since loading its table is the slow part
my $collator;

=head1 NAME

Ged2site::Display::military - list the people who have military records

=head1 SYNOPSIS

	# page.fcgi does this when it is asked for ?page=military
	my $display = Ged2site::Display::military->new({ info => $info, ... });
	print $display->as_string({ military => $military, people => $people });

=head1 DESCRIPTION

Joins the C<military> table (C<entry!person!date!place!notes>, one row per
record) to the C<people> table and renders C<military.tmpl> with one entry
per person, sorted by name.

=encoding utf8

=head1 METHODS

=head2 html

Purpose: build the list of people with military records and render the page.

Arguments: C<military> (a L<Ged2site::DB::military>) and C<people> (a
L<Ged2site::DB::people>), as a hash or a hashref.  Other arguments, which
C<page.fcgi> passes to every page, are ignored.

Returns: the HTML of the page, from L<Web::VWF::Display/html>.

Side effects: reads both tables, through their caches.

When there is no C<military> argument, or no file behind it, or no record in it
refers to someone in C<people>, the template is rendered without C<military>
and says that no one has a military record.

=head3 EXAMPLE

	my $html = $display->html({
		military => Ged2site::DB::military->new(),
		people => Ged2site::DB::people->new(),
	});

	# The template is given:
	#	military => [ { person => 'I112', title => 'Albert Horne 1890 - 1960' }, ... ],
	#	updated => 1762000000

=head3 API SPECIFICATION

=head4 INPUT

	{
		military => { type => 'object', can => 'selectall_arrayref', optional => 1 },
		people => { type => 'object', can => [ 'selectall_arrayref', 'updated' ], optional => 1 },
	}

C<people> is required whenever C<military> is given.

=head4 OUTPUT

	{ type => 'string' }

=head3 MESSAGES

	Message                              Meaning / resolution
	-----------------------------------  ----------------------------------------
	html: 'people' database not given    The caller passed military but not
	                                     people.  Pass both, as page.fcgi does.
	Anything from Database::Join or      Re-thrown.  A missing military file is
	Database::Abstraction                not an error and is not re-thrown.

=head3 FORMAL SPECIFICATION

	[XREF, TITLE]

	Military == seq XREF                -- the person column, one per record
	People == XREF ⇸ TITLE

	html
	ΞMilitary; ΞPeople
	military? : Military
	people? : People
	result! : seq (XREF × TITLE)

	ran result! = { x : ran military? | x ∈ dom people? • (x, people? x) }
	#result! = #(ran result!)                       -- no one is listed twice
	∀ i, j : dom result! | i < j •
		key(second(result! i)) ≤ key(second(result! j))

where C<key> is the level 1 Unicode collation key of the decoded HTML.

=head3 PSEUDOCODE

	if no military database: render the empty page
	croak unless there is a people database
	rows := inner join of military.person to people.entry, or none if
		military has no file
	keep the first row for each person, as (person, title)
	sort by name (Unicode collation of the decoded HTML)
	render the page with the rows, or the empty page if there are none

=cut

sub html {
	my $self = shift;
	my $args = Params::Get::get_params(undef, \@_) // {};

	# page.fcgi always passes one, but the page can be rendered without it
	my $military = $args->{'military'};
	return $self->SUPER::html() unless($military);

	my $people = $args->{'people'} or croak(__PACKAGE__, "::html: 'people' database not given");

	my $records = _people_with_records($military, $people);
	return $self->SUPER::html() unless(scalar(@{$records}));

	return $self->SUPER::html({ military => $records, updated => $people->updated() });
}

# Purpose:      Find the people who have military records, once each, in the
#               order they are listed on the page.
#
# Entry:        $military - Database::Abstraction object for military.csv.
#               $people - Database::Abstraction object for people.csv.
#
# Exit:         Arrayref of { person => xref, title => title } hashrefs, sorted
#               by name.  Empty if there's no military file, or none of its
#               records is of someone in people.csv.
#
# Side Effects: None, other than the tables' caches.
#
# Notes:        Only person and title are kept.  The joined rows have the whole
#               of the person's people.csv row, including the biography and
#               map, which the template doesn't use but would otherwise be
#               copied into its stash.  The join is inner, so a record of
#               someone who isn't in people.csv, and so has no title or page to
#               link to, is left out rather than listed with no name.
sub _people_with_records
{
	my ($military, $people) = @_;

	my $rows = eval {
		Database::Join->new(
			databases => [ $military, $people ],
			join_column => $JOIN_COLUMN,
			join_map => { 1 => $PEOPLE_KEY },
			join_type => 'inner',
			# Both tables have a notes column, so keep them apart
			collision_prefix => { 1 => 'people' },
		)->selectall_arrayref();
	};
	if(my $error = $@) {
		# Re-throw anything other than there being no military records
		croak($error) unless($error =~ $NO_TABLE);
	}

	# Someone with several records, e.g. in both World Wars, is listed once
	my %seen;
	my @records = map { +{ person => $_->{$JOIN_COLUMN}, title => $_->{'title'} } }
		grep { !$seen{$_->{$JOIN_COLUMN}}++ } @{$rows // []};

	# Schwartzian transform, since making the key is not cheap
	return [
		map { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map { [ _sort_key($_->{'title'}), $_ ] } @records
	];
}

# Purpose:      Make the key that titles are sorted by, so that names are in
#               the order a reader expects.
#
# Entry:        $title - a title from people.csv, which is HTML, since ged2site
#               writes accented letters as entities (e.g. "Ren&eacute;").
#
# Exit:         A binary string, to be compared with cmp.
#
# Side Effects: Creates $collator on the first call.
#
# Notes:        Sorting the HTML put "&Eacute;mile" before "Adam", since "&" is
#               before the letters, and comparing the decoded text with cmp
#               would put accented letters after "z".
sub _sort_key
{
	my $title = shift;

	$collator //= Unicode::Collate->new(level => $COLLATION_LEVEL);

	return $collator->getSortKey(HTML::Entities::decode_entities($title // ''));
}

=head1 LIMITATIONS

=over 4

=item The page shows only names

The date, place and notes of each record are in military.csv but are not
shown.  Showing them would mean grouping the records by person instead of
keeping only the first.

=item The join reads more of people.csv than it needs

The left side of the join is about a hundred rows, but Database::Join reads the
people table to match them, which is the slow part of the page (about 0.4s on
a tree of 3,800 people, against 0.07s for looking up each title with
C<< $people->title(entry => $xref) >>), and it grows with the tree.

=item Missing file detection matches a message

Database::Abstraction has no way to ask whether a table has a file, other than
trying to read it, so a missing military.csv is recognised by its documented
error message.  If that message changes, a tree without military records will
get an error page instead of the "no one" page.

=item Only English

There is only an English template.  It is also in
F<templates/default/web>, which other languages fall back to, so that they get
an English page rather than an error.

=back

=cut

1;
