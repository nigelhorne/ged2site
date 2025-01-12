package Ged2site::Display::history;

# Display the history page

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

# Generate HTML for the history page
sub html {
	my $self = shift;

	# Allow arguments to be passed as either a hash reference or a list
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Access the CGI::Info object
	my $info = $self->{_info};

	# Define the allowed parameters with their respective validation rules
	my $allowed = {
		page => 'history',	# Static value for the page
		entry => undef,	# TODO: Add a regex for valid entry (XREF) formats
		lang => qr/^[A-Z][A-Z]/i,	# Language code (e.g., EN, FR)
		lint_content => qr/^\d$/,	# Single-digit numeric content
		fbclid => qr/^[\w-]+$/i,	# Facebook tracking information
		gclid => qr/^\w+$/i,	# Google tracking information
	};

	# Extract parameters from the request, applying the validation rules
	my %params = %{$info->params({ allow => $allowed })};

	# Get the history database handle
	my $history = $args{'history'};

	# TODO: handle situation where look up fails

	# Array to store events
	my @events;

	# Prepare template arguments with an updated timestamp from the database
	my $template_args = { updated => $history->updated() };

	if(my $entry = $params{'entry'}) {
		# Fetch timeline events for a specific person

		# TODO: add items such as emigration, world events
		@events = $history->selectall_hash({ person => $entry });

		# If events are found, set the person's name in the template arguments
		if(scalar(@events)) {
			$template_args->{'name'} = $events[0]->{'title'};
		}

		# Get the people database handle
		my $people = $args{'people'};

		# Fetch person details based on the entry parameter
		if(my $person = $people->fetchrow_hashref({ entry => $entry })) {
			# Get the year of death of the person being displayed
			my $yod;
			if($person->{'dod'} && ($person->{'dod'} =~ /^(\d{3,4})\/\d{2}\/\d{2}$/)) {
				$yod = $1;
			}

			# Process mother and father
			foreach my $parent('mother', 'father') {
				if($person->{$parent} && ($person->{$parent} =~ /&entry=(\w+)">/)) {
					my $xref = $1;

					# Fetch details of this parent
					my $other = $people->fetchrow_hashref({ entry => $xref });

					# If the parent has a valid date of death, format it
					if($other->{'dod'} && ($other->{'dod'} =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/)) {
						my $year = $1;
						my $month = $2;
						my $day = $3;

						# Only include on this person's timeline if the parent died
						#	before they did
						next if(defined($yod) && ($year > $yod));

						# Remove leading zeros from day and month
						$day =~ s/^0//;
						$month =~ s/^0//;

						# Add a "Death of parent" event to the timeline
						push @events, {
							event => "Death of $parent",
							person => $xref,
							title => $other->{'title'},
							day => $day,
							month => $month,
							year => $year,
						}
					}
				}
			}
			# Process children
			foreach my $child(split(/----/, $person->{'children'})) {
				my $name;
				if($child =~ /">(.+)<\/a>/) {
					$name = $1;
				} else {
					$name = 'Unknown child';
				}
				if($child =~ /&entry=(\w+)">/) {
					my $xref = $1;

					# Fetch details of this child
					my $other = $people->fetchrow_hashref({ entry => $xref });

					# If the child person has a valid date of birth, format it
					if($other->{'dob'} && ($other->{'dob'} =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/)) {
						my $year = $1;
						my $month = $2;
						my $day = $3;

						# Remove leading zeros from day and month
						$day =~ s/^0//;
						$month =~ s/^0//;

						# Add a "Birth of child" event to the timeline
						push @events, {
							event => 'Birth of child',
							person => $xref,
							title => $other->{'title'},
							day => $day,
							month => $month,
							year => $year,
						}
					}
					# If the child person has a valid date of death, format it
					if($other->{'dod'} && ($other->{'dod'} =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/)) {
						my $year = $1;
						my $month = $2;
						my $day = $3;

						# Only include on this person's timeline if the child died
						#	before they did
						next if(defined($yod) && ($year > $yod));

						# Remove leading zeros from day and month
						$day =~ s/^0//;
						$month =~ s/^0//;

						# Add a "Death of child" event to the timeline
						push @events, {
							event => 'Death of child',
							person => $xref,
							title => $other->{'title'},
							day => $day,
							month => $month,
							year => $year,
						}
					}
				}
			}
		}

		# Sort events by year in ascending order
		@events = sort { $a->{'year'} <=> $b->{'year'} } @events;
	} else {
		# If no specific "entry" is provided, fetch events for all people
		@events = $history->selectall_hash();
	}
	
	# Group events by year into a hash
	my $eventshash;	# Hash to store events grouped by year

	foreach my $event(@events) {
		push @{$eventshash->{$event->{'year'}}}, $event;
	}

	# Add grouped events to the template arguments
	$template_args->{'events'} = $eventshash;

	# Call the parent class's html method to render the final HTML
	return $self->SUPER::html($template_args);
}

1;
