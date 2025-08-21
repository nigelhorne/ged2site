package Ged2site::Display::censuses;

# Display the censuses page

use Ged2site::Display;

use parent 'Ged2site::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'censuses',
		'census' => undef,	# TODO: regex of allowable name formats
		'lang' => qr/^[A-Z]{2}$/i,
		'lint_content' => qr/^\d$/,
	};
	# Handles into the databases
	if(my $censuses = $args{'censuses'}) {
		my $people = $args{'people'};

		my $params = $self->{'_info'}->params({ allow => $allowed });

		if(!$params->{'census'}) {
			# Display list of censuses
			my @c = $censuses->census(distinct => 1);
			@c = sort @c;
			return $self->SUPER::html({ censuses => \@c, updated => $censuses->updated() });
		}

		# delete $params->{'page'};
		# delete $params->{'lint_content'};
		# delete $params->{'lang'};

		# Look in the censuses.csv for the name given as the CGI argument and
		# find their details
		if(my $census = $censuses->selectall_hashref({ census => $params->{'census'}})) {
			my @people = sort { $a->{'title'} cmp $b->{'title'} } map { $people->fetchrow_hashref({ entry => $_->{'person'} }) } @{$census};

			return $self->SUPER::html({ census => $census, people => \@people, updated => $censuses->updated() });
		} elsif($self->{'logger'}) {
			$self->{'logger'}->notice(__PACKAGE__, ": census $params->{census} not found");
		}
		return $self->SUPER::html({ censuses => $censuses, error => "Census $params->{census} not found", updated => $censuses->updated() });
	}
	# No census database
	return $self->SUPER::html();
}

1;
