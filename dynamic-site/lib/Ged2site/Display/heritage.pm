package Ged2site::Display::heritage;

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak carp);
use Params::Get;
use Readonly;
use parent 'Ged2site::Display';

=encoding ASCII

=head1 NAME

Ged2site::Display::heritage - Render the Heritage page

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

# Field name used to sort people within each country group
Readonly my $SORT_KEY => 'title';

# Minimum acceptable length for a birth_country value
Readonly my $MIN_COUNTRY_LEN => 1;

=head1 SYNOPSIS

    my $page = Ged2site::Display::heritage->new(%display_args);
    print $page->as_string({ heritage => $heritage_db_handle });

=head1 DESCRIPTION

Renders the Heritage page of a Ged2site genealogy website.
The page lists blood relatives of the home person who were born in a
different country, grouped by country and sorted alphabetically by
full name within each group.

Row data is read from the C<heritage.csv> data file, which has the
schema: C<entry!title!birth_country!dob!relationship>.
Rows with an empty C<birth_country> are silently skipped.

=head1 SUBROUTINES/METHODS

=head2 html

Generate and return the Heritage HTML page.

=head3 PURPOSE

Reads all rows from the heritage database handle, groups them by
C<birth_country> (skipping rows without one), sorts each group
alphabetically by C<title>, and delegates final rendering to the
parent class Template Toolkit renderer.

=head3 ARGUMENTS

Takes either a plain hash or a hash reference.

=over 4

=item * C<heritage> (required)

A C<Ged2site::DB::heritage> handle (or any C<Database::Abstraction>
subclass) that responds to C<selectall_hash()> and C<updated()>.
Croaks if absent or false.

=back

=head3 RETURNS

A non-empty scalar string containing the fully rendered HTML page.

=head3 SIDE EFFECTS

Inherits any Template Toolkit I/O and logging side effects from
C<Ged2site::Display::html>.

=head3 EXAMPLE

    # Typical call from page.fcgi
    my $html = $display->html({ heritage => $heritage_db });
    print $html;

=head3 API SPECIFICATION

=head4 Input

Schema compatible with Params::Validate::Strict:

    {
        heritage => {
            type => Params::Validate::OBJECT,
            can  => [qw(selectall_hash updated)],
        },
    }

=head4 Output

Schema compatible with Return::Set:

    {
        type        => 'Scalar',
        description => 'Rendered HTML string produced by Template Toolkit',
        defined     => 1,
        nonempty    => 1,
    }

=head3 MESSAGES

=over 4

=item C<heritage parameter is required>

Croaked when no C<heritage> argument is supplied, or when the value
is false (undef, 0, or empty string).  Pass a valid
C<Ged2site::DB::heritage> database handle.

=back

=head3 FORMAL SPECIFICATION

    [HTML, DB_Handle, COUNTRY, PERSON]

    Heritage_Row == [|
        entry         : STRING;
        title         : STRING;
        birth_country : COUNTRY;
        dob           : STRING;
        relationship  : STRING
    |]

    -- Predicate: a row has a usable country value
    has_country : Heritage_Row --> Boolean
    has_country r <=> r.birth_country /= ''

    -- Grouping function: for each country, the sorted sequence of rows
    by_country : COUNTRY -|-> seq Heritage_Row
    by_country = (lambda c : COUNTRY @
                      sort_by(title,
                          { r : Heritage_Row | r.birth_country = c }))

    -- Main operation schema
    HERITAGE_HTML __________________________________________
    db!     : DB_Handle
    result! : HTML_String
    _______________________________________________________
    pre  HERITAGE_HTML <=> db! /= null
                       /\ responds_to(db!, selectall_hash)
                       /\ responds_to(db!, updated)

    let rows  == db!.selectall_hash() @
    let valid == { r : rows | has_country(r) } @

    result! = SUPER_html({
        heritage_by_country |-> by_country / valid,
        updated             |-> db!.updated()
    })

    post HERITAGE_HTML <=> result! /= ''
    ________________________________________________________

=cut

sub html
{
	my $self = shift;

	# Normalise hash or hashref arguments using Params::Get
	my $params = Params::Get::get_params(undef, @_);

	# Validate the mandatory heritage database handle
	my $heritage = $params->{'heritage'}
		or croak 'heritage parameter is required';

	# Fetch all rows from the heritage data source
	my @everyone = $heritage->selectall_hash();

	# Group rows by birth country, dropping any row without one
	my %by_country;
	for my $person (@everyone) {
		my $country = $person->{'birth_country'};

		# Skip rows with missing or empty birth_country
		next unless defined($country) && length($country) >= $MIN_COUNTRY_LEN;

		push @{$by_country{$country}}, $person;
	}

	# Sort each country group alphabetically by title
	for my $country (keys %by_country) {
		$by_country{$country} = [
			sort { ($a->{$SORT_KEY} // '') cmp ($b->{$SORT_KEY} // '') }
			@{$by_country{$country}}
		];
	}

	# Delegate to the parent Template Toolkit renderer
	return $self->SUPER::html({
		heritage_by_country => \%by_country,
		updated             => $heritage->updated(),
	});
}

1;

__END__

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Ged2site is licensed under GPL2.0 for personal use only.
Commercial users must apply in writing for a licence.

=head1 SEE ALSO

L<Ged2site::DB::heritage>, L<Ged2site::Display>, L<Database::Abstraction>

=cut
