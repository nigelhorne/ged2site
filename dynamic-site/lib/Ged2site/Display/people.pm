package Ged2site::Display::people;

use warnings;
use strict;

# Display the people page

use Ged2site::Display;
use MIME::Base64;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	die unless($info);

	my $allowed = {
		'page' => 'people',
		'entry' => undef,	# TODO: regex of allowable name formats
		'home' => 1,
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
		'fbclid' => qr/^[\w-]+$/i,	# Facebook info
		'gclid' => qr/^\w+$/i,	# Google info
	};
	my %params = %{$info->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	my $people = $args{'people'};	# Handle into the database

	unless(scalar(keys %params)) {
		# Display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	# Look in the people.csv for the name given as the CGI argument and
	# find their details
	# TODO: handle situation where look up fails

	return $self->SUPER::html({
		person => $people->fetchrow_hashref(\%params),
		decode_base64url => sub { MIME::Base64::decode_base64url($_[0]); },
		updated => $people->updated()
	});
}

1;
