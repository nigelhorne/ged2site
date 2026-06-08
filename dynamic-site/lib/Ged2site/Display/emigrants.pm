package Ged2site::Display::emigrants;

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak carp);
use Params::Get;
use Readonly;
use parent 'Ged2site::Display';

our $VERSION = '0.01';

# Boundaries of the two world wars used to exclude war-related deaths
# from the emigrant classification.  People who died in these ranges
# are assumed to have moved under duress, not by choice.
Readonly my $WWI_START  => 1914;
Readonly my $WWI_END    => 1918;
Readonly my $WWII_START => 1939;
Readonly my $WWII_END   => 1945;

# Field used to sort people within a country group
Readonly my $SORT_KEY => 'title';

=encoding ASCII

=head1 NAME

Ged2site::Display::emigrants - Render the Emigrants page

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    my $page = Ged2site::Display::emigrants->new(%display_args);
    print $page->as_string({ people => $people_db_handle });

=head1 DESCRIPTION

Renders the Emigrants page, which lists people from the genealogy
database who were born in one country and died in another.
Deaths during WWI (1914-1918) or WWII (1939-1945) are excluded on
the assumption that those were wartime displacements rather than
voluntary emigration.

=head1 SUBROUTINES/METHODS

=head2 html

Generate and return the Emigrants HTML page.

=head3 PURPOSE

Fetch all person records from the people database, filter to those
who qualify as emigrants (different birth/death countries, not during
a world war), group by death country, sort each group by title, and
pass the result to the parent Template Toolkit renderer.

=head3 ARGUMENTS

Takes either a plain hash or a hash reference.

=over 4

=item * C<people> (required)

A C<Ged2site::DB::people> handle (or compatible C<Database::Abstraction>
subclass) responding to C<selectall_hash()> and C<updated()>.
Croaks if absent.

=back

=head3 RETURNS

A non-empty scalar string containing the rendered HTML page.

=head3 SIDE EFFECTS

Inherits any Template Toolkit I/O and logging side effects from
C<Ged2site::Display::html>.

=head3 EXAMPLE

    my $html = $display->html({ people => $people_db });

=head3 API SPECIFICATION

=head4 Input

Schema compatible with Params::Validate::Strict:

    {
        people => {
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

=item C<people parameter is required>

Croaked when no C<people> argument is supplied.  Pass a valid
C<Ged2site::DB::people> database handle.

=back

=head3 FORMAL SPECIFICATION

    [HTML, DB_Handle, COUNTRY, YEAR, PERSON]

    -- A person record qualifies as an emigrant when:
    --   1. Both birth_country and death_country are non-empty
    --   2. birth_country /= death_country
    --   3. Year of death is not in a world-war range
    is_emigrant : PERSON --> Boolean
    is_emigrant p <=>
        p.birth_country /= '' /\ p.death_country /= ''
        /\ p.birth_country /= p.death_country
        /\ NOT(year_of(p.dod) in WWI_START..WWI_END)
        /\ NOT(year_of(p.dod) in WWII_START..WWII_END)

    emigrants : DB_Handle --> seq PERSON
    emigrants db = sort_by(title,
                      { p : db.selectall_hash() | is_emigrant(p) })

    by_death_country : (seq PERSON) --> COUNTRY -|-> seq PERSON
    by_death_country ps =
        (lambda c : COUNTRY @ sort_by(title,
                                  { p : ps | p.death_country = c }))

    EMIGRANTS_HTML _____________________________________
    db!     : DB_Handle
    result! : HTML_String
    ____________________________________________________
    pre  EMIGRANTS_HTML <=> db! /= null
                        /\ responds_to(db!, selectall_hash)
                        /\ responds_to(db!, updated)

    let es == emigrants(db!) @
    result! = SUPER_html({
        emigrants           |-> es,
        emigrants_by_country |-> by_death_country(es),
        updated             |-> db!.updated()
    })
    ____________________________________________________

=cut

sub html
{
	my $self = shift;

	# Normalise hash or hashref arguments
	my $params = Params::Get::get_params(undef, @_);

	# Validate the mandatory people database handle
	my $people = $params->{'people'}
		or croak 'people parameter is required';

	# Fetch every person record
	my @everyone = $people->selectall_hash();

	# Keep only those who qualify as emigrants
	my @emigrants = grep { _is_emigrant($_) } @everyone;

	# Sort the full list alphabetically by name
	@emigrants = sort { ($a->{$SORT_KEY} // '') cmp ($b->{$SORT_KEY} // '') }
	             @emigrants;

	# Group emigrants by death country for the template
	my %by_country;
	for my $e (@emigrants) {
		push @{$by_country{$e->{'death_country'}}}, $e;
	}

	# Sort each country group alphabetically by name
	for my $country (keys %by_country) {
		$by_country{$country} = [
			sort { ($a->{$SORT_KEY} // '') cmp ($b->{$SORT_KEY} // '') }
			@{$by_country{$country}}
		];
	}

	# Hand off to the parent Template Toolkit renderer
	return $self->SUPER::html({
		emigrants            => \@emigrants,
		emigrants_by_country => \%by_country,
		updated              => $people->updated(),
	});
}

# Purpose: decide whether a person qualifies as an emigrant.
# Entry criteria: $person is a hashref with birth_country, death_country, and dod keys.
# Exit status: returns 1 (emigrant) or 0 (not an emigrant).
# Side effects: none.
# Notes: excludes people whose year of death falls within either world war.
sub _is_emigrant
{
	my $person = shift;

	# Both country fields must exist and be defined
	return 0 unless defined($person->{'birth_country'})
	             && defined($person->{'death_country'});
	return 0 unless length($person->{'birth_country'})
	             && length($person->{'death_country'});

	# Emigrant: born in one country, died in another
	return 0 if $person->{'birth_country'} eq $person->{'death_country'};

	# Deaths during world wars are excluded (wartime displacement, not emigration)
	if(my $dod = $person->{'dod'}) {
		if(my $year = _year_from_date($dod)) {
			return 0 if $year >= $WWI_START  && $year <= $WWI_END;
			return 0 if $year >= $WWII_START && $year <= $WWII_END;
		}
	}

	return 1;
}

# Purpose: extract a 4-digit year from a date string.
# Entry criteria: $date is a string, typically in YYYY/MM/DD or plain YYYY format.
# Exit status: returns year as an integer, or undef if the format is unrecognised.
# Side effects: none.
# Notes: supports GEDCOM-style date strings produced by ged2site.
sub _year_from_date
{
	my $date = shift;

	return unless defined $date;

	# YYYY/MM/DD format -- capture the leading year group
	if($date =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
		return $1 + 0;	# Force numeric context to strip leading zeros
	}

	# Plain YYYY format
	if($date =~ /^(\d{3,4})$/) {
		return $1 + 0;
	}

	return;
}

1;

__END__

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Ged2site is licensed under GPL2.0 for personal use only.

=head1 SEE ALSO

L<Ged2site::DB::people>, L<Ged2site::Display>

=cut
