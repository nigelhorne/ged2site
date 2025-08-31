package Ged2site::Display::people;

use warnings;
use strict;

# Display the people page

use Data::Dumper;
use Ged2site::Display;
use MIME::Base64;

use parent 'Ged2site::Display';

# Build the "people" page by validating incoming request parameters, querying the database for a matching person record, and preparing structured data (including Schema.org JSON-LD).
# If no valid parameters are provided, or no record is found, it falls back to rendering the main index page with optional error information.
# The result is passed to the parent html method along with the person details, schema.org metadata, and helper utilities for rendering.

sub html {
	my $self = shift;
	my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

	my $info = $self->{_info};
	die 'Missing _info in object' unless $info;

	# Define allow parameters (use state to avoid redeclaring in subsequent calls)
	# state $allow = {
	my $allow = {
		page => 'people',
		entry => undef,	# TODO: Add regex for valid formats
		home => 1,
		lang => qr/^[A-Z]{2}$/i,
		fbclid => qr/^[\w\-]+$/i,	# Facebook tracking info
		gclid => qr/^\w+$/i,	# Google tracking info
		'lint_content' => qr/^\d$/,
	};

	# Database handle
	my $people = $args{'people'};
	die "Missing 'people' handle" unless($people);

	# Extract and filter params
	my $params = $info->params({ allow => $allow });

	if(!defined($params)) {
		# No parameters given: display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	# Parameters to exclude from further processing
	delete @$params{qw(page lint_content lang fbclid gclid)};

	if(scalar(keys %{$params}) == 0) {
		# No parameters to process: display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	# Fetch person details from the database
	my $person_details = $people->fetchrow_hashref($params);
	unless($person_details) {
		my $error = __PACKAGE__ . ': No matching record found for given parameters: ' . join(', ', keys %{$params}) . ", entry = '" . ($params->{entry} // 'undef') . "'";
		if($self->{'logger'}) {
			$self->{'logger'}->warn($error);
		}
		return $self->SUPER::html(updated => $people->updated(), error => $error);
	}

	my $gender = uc($person_details->{'sex'} // '');
	$gender = ($gender eq 'M') ? 'Male' : ($gender eq 'F') ? 'Female' : 'Unknown';

	my $schema_org = {
		'@context' => 'https://schema.org',
		'@type' => 'Person',
		(defined $person_details->{title} ? (name => $person_details->{title}) : ()),
		(defined $person_details->{dob} ? (birthDate => $person_details->{dob}) : ()),
		gender => $gender,
	};

	if(my $logger = $self->{'logger'}) {
		$logger->debug('Schema.org: ' . Data::Dumper->new([$schema_org])->Dump());
	}

	# Render the response with person details
	return $self->SUPER::html({
		person => $person_details,
		# decode_base64url => sub { MIME::Base64::decode_base64url($_[0]); },
		decode_base64url => \&MIME::Base64::decode_base64url,
		schema_org => $schema_org,
		updated => $people->updated()
	});
}

1;
