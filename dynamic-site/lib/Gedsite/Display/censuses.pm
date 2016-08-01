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
		'entry' => undef,	# TODO: regex of allowable name formats
	};
	my $params = $info->params({ allowed => $allowed });
	if($params && $params->{'page'}) {
		delete $params->{'page'};
	}

	my $censuses = $args{'censuses'};	# Handle into the database

	unless($params && scalar(keys %{$params})) {
		my @c = $censuses->census();
		# Display the main index page
		return $self->SUPER::html({ censuses => \@c });
	}

	# Look in the censuses.csv for the name given as the CGI argument and
	# find their details
	my $census = $censuses->fetchrow_hashref($params);

	# TODO: handle situation where look up fails

	return $self->SUPER::html({ census => $census });
}

1;
