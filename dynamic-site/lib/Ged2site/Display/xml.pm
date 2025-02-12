package Ged2site::Display::xml;

# Send the XML file of a person

use warnings;
use strict;
use File::Slurp;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub http
{
	return "Content-Type: text/xml\n\n";
}

sub html
{
	my $self = shift;

	my $logger = $self->{'_logger'};
	if($logger) {
		$logger->trace(__PACKAGE__, ': entering html()');
	}

	# Allow arguments to be passed as either a hash reference or a list
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Access the CGI::Info object
	my $info = $self->{_info};

	# Define the allowed parameters with their respective validation rules
	my $allowed = {
		page => 'xml',	# Static value for the page
		entry => undef,	# TODO: Add a regex for valid entry (XREF) formats
		lang => qr/^[A-Z][A-Z]/i,	# Language code (e.g., EN, FR)
		lint_content => qr/^\d$/,	# Single-digit numeric content
		fbclid => qr/^[\w-]+$/i,	# Facebook tracking information
		gclid => qr/^\w+$/i,	# Google tracking information
	};

	# Extract parameters from the request, applying the validation rules
	my %params = %{$info->params({ allow => $allowed })};

	if(my $entry = $params{'entry'}) {
		return _get_person(\%args, \%params);
	}
	return $self->SUPER::html({ error => 'entry parameter not given' });
}

# Helper: Get a hashref of the data for this person
sub _get_person
{
	my($args, $params) = @_;

	my $filename = File::Spec->catfile($args->{'database_dir'}, 'people', $params->{'entry'}) . '.xml';
	if(-r $filename) {
		# Read in the .../data/people/$xref.xml file
		return File::Slurp::read_file($filename);
	}

	return 'Not found';
}

1;
