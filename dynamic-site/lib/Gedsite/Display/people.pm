package Gedsite::Display::people;

# Display the people page

use Gedsite::Display::page;

our @ISA = ('Gedsite::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'people',
		'entry' => undef,	# TODO: regex of allowable name formats
	};
	my $params = $info->params({ allowed => $allowed });
	if($params && $params->{'page'}) {
		delete $params->{'page'};
	}
	unless($params && scalar(keys %{$params})) {
		# Display the main index page
		return $self->SUPER::html();
	}

	my $people = $args{'people'};	# Handle into the database

	# Look in the people.csv for the name given as the CGI argument and
	# find their details
	my $person = $people->fetchrow_hashref($params);

	# TODO: handle situation where look up fails

	return $self->SUPER::html({ person => $person });
}

1;
