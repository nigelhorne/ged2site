package Ged2site::Display::emigrants;

use warnings;
use strict;

# Display the emigrants page

use parent 'Ged2site::Display';

# Generate HTML for the emigrants page
sub html
{
	my $self = shift;

	# Handle hash or hashref arguments
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Ensure 'people' is provided
	my $people = $args{'people'};
	die "Error: 'people' parameter is missing or invalid" unless($people);

	# Retrieve all people
	my @everyone = $people->selectall_hash();

	# Filter emigrants
	my @emigrants = grep { _is_emigrant($_) } @everyone;

	# Sort emigrants by title
	@emigrants = sort { ($a->{'title'} // '') cmp ($b->{'title'} // '') } @emigrants;

	my %by_country;

	# Group by death_country
	for my $e (@emigrants) {
		push @{ $by_country{$e->{'death_country'}} }, $e;
	}

	# Sort each country group by title
	for my $country (keys %by_country) {
		my @sorted = sort {
			($a->{'title'} // '') cmp ($b->{'title'} // '')
		} @{ $by_country{$country} };

		$by_country{$country} = \@sorted;
	}

	# Return HTML with emigrants data
	return $self->SUPER::html({
		emigrants => \@emigrants,
		emigrants_by_country => \%by_country,
		updated => $people->updated()
	});

	# Helper: determines if a person is an emigrant
	sub _is_emigrant
	{
		my $person = shift;

		# Check if birth and death countries exist
		return 0 unless(exists($person->{'birth_country'}) && exists($person->{'death_country'}));
		return 0 unless(defined($person->{'birth_country'}) && defined($person->{'death_country'}));

		# Skip if birth and death countries are the same
		return 0 if($person->{'birth_country'} eq $person->{'death_country'});

		# Check if death occurred during a war period
		if(my $dod = $person->{'dod'}) {
			if(my $yod = _get_year_from_date($dod)) {
				return 0 if(($yod >= 1914) && ($yod <= 1918));	# WWI
				return 0 if(($yod >= 1939) && ($yod <= 1945));	# WWII
			}
		}

		return 1;	# Person is an emigrant

		# Helper: extract year from date
		sub _get_year_from_date
		{
			my $dod = shift;

			if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {	# YYYY/MM/DD format
				$dod =~ tr/\//-/;	# Normalize date format
				return $1;	# Extract year
			} elsif($dod =~ /^\d{3,4}$/) {	# YYYY format
				return $dod;
			}

			return;	# Return undefined if format doesn't match
		}
	}
}

1;
