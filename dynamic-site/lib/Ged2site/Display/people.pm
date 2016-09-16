package Ged2site::Display::people;

# Display the people page

use Ged2site::Display::page;
use MIME::Base64;

our @ISA = ('Ged2site::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'people',
		'entry' => undef,	# TODO: regex of allowable name formats
		'home' => 1,
	};
	my $params = $info->params({ allow => $allowed });
	if($params && $params->{'page'}) {
		delete $params->{'page'};
	}

	my $people = $args{'people'};	# Handle into the database

	unless($params && scalar(keys %{$params})) {
		# Display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	# Look in the people.csv for the name given as the CGI argument and
	# find their details
	my $person = $people->fetchrow_hashref($params);

	# TODO: handle situation where look up fails

	return $self->SUPER::html({
		person => $person,
		decode_base64url => sub {
			MIME::Base64::decode_base64url($_[0])
		},
		updated => $people->updated()
	});
}

1;
