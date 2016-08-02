package Gedsite::Display::censuses;

# Display the censuses page

use Gedsite::Display::page;

our @ISA = ('Gedsite::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'censuses',
		'census' => undef,	# TODO: regex of allowable name formats
	};
	my $params = $info->params({ allow => $allowed });
	if($params && $params->{'page'}) {
		delete $params->{'page'};
	}

	# Handles into the databases
	my $censuses = $args{'censuses'};
	my $people = $args{'people'};

	unless($params && scalar(keys %{$params})) {
		# Display the main index page
		my @c = $censuses->census();
		return $self->SUPER::html({ censuses => \@c });
	}

	# Look in the censuses.csv for the name given as the CGI argument and
	# find their details
	my $census = $censuses->selectall_hashref($params);
	my @people;

	foreach my $person(@{$census}) {
		push @people, $people->fetchrow_hashref({ entry => $person->{'person'} });
	}

	# TODO: handle situation where look up fails
	return $self->SUPER::html({ census => $census, people => \@people });
}

1;
