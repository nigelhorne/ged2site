package Ged2site::Display::heritage;

# Display the heritage page: blood relatives born in a different country than the home person

use warnings;
use strict;

use parent 'Ged2site::Display';

sub html
{
	my $self = shift;

	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $heritage = $args{'heritage'};
	die "Error: 'heritage' parameter is missing or invalid" unless $heritage;

	my @everyone = $heritage->selectall_hash();

	my %by_country;
	for my $person (@everyone) {
		next unless defined($person->{'birth_country'}) && length($person->{'birth_country'});
		push @{$by_country{$person->{'birth_country'}}}, $person;
	}

	for my $country (keys %by_country) {
		$by_country{$country} = [
			sort { ($a->{'title'} // '') cmp ($b->{'title'} // '') }
			@{$by_country{$country}}
		];
	}

	return $self->SUPER::html({
		heritage_by_country => \%by_country,
		updated             => $heritage->updated(),
	});
}

1;
