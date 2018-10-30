package Ged2site::Display::military;

# Display the Military Records page

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my @military = $args{'military'}->selectall_hash();

	my $people = $args{'people'} || die;

	# Lookup the full name of the person
	foreach my $person(@military) {
		$person->{'title'} = $people->title(entry => $person->{'person'});
	}

	@military = sort { $a->{'title'} cmp $b->{'title'} } @military;

	return $self->SUPER::html({ military => \@military, updated => $people->updated() });
}

1;
