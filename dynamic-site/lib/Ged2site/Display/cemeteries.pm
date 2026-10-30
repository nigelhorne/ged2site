package Ged2site::Display::cemeteries;

# Display the list of cemeteries

use warnings;
use strict;
use VWF::Display;

use parent 'VWF::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'cemeteries',
		'lang' => qr/^[A-Za-z]{2}$/,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$self->{'_info'}->params({ allow => $allowed })};

	my $people = $args{'people'};
	my @all_cemeteries = $args{'cemeteries'}->entry();
	my @cemeteries;
	foreach my $cemetery(sort @all_cemeteries) {
		# entry!xref1,xref2

		my $xrefs = $args{cemeteries}->xrefs($cemetery);
		my @cemetery_people;
		foreach my $xref(split /,/, $xrefs) {
			push @cemetery_people, $people->fetchrow_hashref(entry => $xref);
		}
		push @cemeteries, {
			cemetery => $cemetery,
			people => \@cemetery_people
		}
	}
	return $self->SUPER::html({ cemeteries => \@cemeteries, updated => $args{'cemeteries'}->updated() });
}

1;
