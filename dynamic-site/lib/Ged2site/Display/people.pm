package Ged2site::Display::people;

use warnings;
use strict;

# Display the people page

use Ged2site::Display;
use MIME::Base64;

our @ISA = ('Ged2site::Display');

# sub OLD_CODE_html {
	# my $self = shift;
	# my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
# 
	# my $info = $self->{_info};
	# die unless($info);
# 
	# my $allowed = {
		# 'page' => 'people',
		# 'entry' => undef,	# TODO: regex of allowable name formats
		# 'home' => 1,
		# 'lang' => qr/^[A-Z][A-Z]/i,
		# 'lint_content' => qr/^\d$/,
		# 'fbclid' => qr/^[\w-]+$/i,	# Facebook info
		# 'gclid' => qr/^\w+$/i,	# Google info
	# };
	# my %params = %{$info->params({ allow => $allowed })};
# 
	# delete $params{'page'};
	# delete $params{'lint_content'};
	# delete $params{'lang'};
	# delete $params{'fbclid'};
	# delete $params{'gclid'};
# 
	# my $people = $args{'people'};	# Handle into the database
# 
	# unless(scalar(keys %params)) {
		# # Display the main index page
		# return $self->SUPER::html(updated => $people->updated());
	# }
# 
	# # Look in the people.csv for the name given as the CGI argument and
	# # find their details
	# # TODO: handle situation where look up fails
# 
	# return $self->SUPER::html({
		# person => $people->fetchrow_hashref(\%params),
		# decode_base64url => sub { MIME::Base64::decode_base64url($_[0]); },
		# updated => $people->updated()
	# });
# }

sub html {
	my $self = shift;
	my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

	my $info = $self->{_info};
	die "Missing _info in object" unless $info;

	# Define allowed parameters (use state to avoid redeclaring in subsequent calls)
	# state $allowed = {
	my $allowed = {
		page => 'people',
		entry => undef,	# TODO: Add regex for valid formats
		home => 1,
		lang => qr/^[A-Z]{2}$/i,
		lint_content => qr/^\d$/,
		fbclid => qr/^[\w-]+$/i,	# Facebook tracking info
		gclid => qr/^\w+$/i,	# Google tracking info
	};

	# Extract and filter params
	my %params = %{$info->params({ allow => $allowed })};

	# Parameters to exclude from further processing
	# my @exclude_keys = qw(page lint_content lang fbclid gclid);
	# delete @params{@exclude_keys};
	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};
	delete $params{'fbclid'};
	delete $params{'gclid'};

	# Database handle
	my $people = $args{'people'};
	die "Missing 'people' handle" unless($people);

	unless(scalar(keys %params)) {
		# No parameters to process: return the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	# Fetch person details from the database
	my $person_details = $people->fetchrow_hashref(\%params);
	unless($person_details) {
		die 'Lookup failed: No matching record found for given parameters';
	}

	# Render the response with person details
	return $self->SUPER::html({
		person => $person_details,
		decode_base64url => sub { MIME::Base64::decode_base64url($_[0]); },
		updated => $people->updated()
	});
}


1;
