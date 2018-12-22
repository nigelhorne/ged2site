package Ged2site::Display::locations;

# Display the locations page

use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'locations',
		'year' => qr/^\d{4}$/,
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	# Handles into the databases
	my $locations = $args{'locations'};

	if(scalar(keys %params) == 0) {
		# Display list of locations
		my @locations = $locations->locations();
		return $self->SUPER::html({ locations => \@locations, updated => $locations->updated() });
	}

	my $location = $locations->location(year => $params{'year'});

	return $self->SUPER::html({ location => $location, updated => $locations->updated() });
}

1;
