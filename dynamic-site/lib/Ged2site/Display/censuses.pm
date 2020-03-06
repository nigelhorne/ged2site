package Ged2site::Display::censuses;

# Display the censuses page

use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'censuses',
		'census' => undef,	# TODO: regex of allowable name formats
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	# Handles into the databases
	if(my $censuses = $args{'censuses'}) {
		my $people = $args{'people'};

		if(scalar(keys %params) == 0) {
			# Display list of censuses
			my @c = $censuses->census(distinct => 1);
			@c = sort @c;
			return $self->SUPER::html({ censuses => \@c, updated => $censuses->updated() });
		}

		# Look in the censuses.csv for the name given as the CGI argument and
		# find their details
		my $census = $censuses->selectall_hashref(\%params);

		my @people = sort map { $people->fetchrow_hashref({ entry => $_->{'person'} }) } @{$census};

		# TODO: handle situation where look up fails
		return $self->SUPER::html({ census => $census, people => \@people, updated => $censuses->updated() });
	}
	# No census database
	return $self->SUPER::html();
}

1;
