package Ged2site::Display::locations;

# Display the locations page

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'locations',
		'year' => qr/^\d{3,4}$/,
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	if(my $db = $args{'locations'}) {
		my @locations = $db->locations();

		my %params = %{$info->params({ allow => $allowed })};

		delete $params{'page'};
		delete $params{'lint_content'};
		delete $params{'lang'};

		if(scalar(keys %params) == 0) {
			# Display list of locations
			return $self->SUPER::html({ locations => \@locations, updated => $db->updated() });
		}

		return $self->SUPER::html({
			head => $db->head(year => $params{'year'}),
			locations => \@locations,
			updated => $db->updated()
		});
	}

	# Locations database doesn't exist
	return $self->SUPER::html();
}

1;
