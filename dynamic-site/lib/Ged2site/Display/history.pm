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

	# Array to store events
	my @events;

	# Prepare template arguments with an updated timestamp from the database
	my $template_args = { updated => $history->updated() };


	if(my $entry = $params{'entry'}) {
		# Fetch timeline events for a specific person

		# TODO: handle situation where look up fails
		# TODO: add items such as emigration, world events
		@events = $history->selectall_hash({ person => $entry });

		# If events are found, pass the person's name to the template
		# The template uses the [% name %] field to know if it's to display a specific person
		#	or all events in the database
		$template_args->{'name'} = $events[0]->{'title'} if(scalar(@events));

		# Get the people database handle
		my $people = $args{'people'};

		# Get the language to display
		my $language = lc($params{'lang'} || $self->{'_lingua'}->language_code_alpha2() || 'en');

		# Fetch person details based on the entry parameter
		if(my $person = $people->fetchrow_hashref({ entry => $entry })) {
			# Get the year of death of the person being displayed
			my ($yod) = parse_date($person->{'dod'});

			# Process mother and father
			foreach my $relation ('mother', 'father') {
				if(my $xref = $person->{$relation} =~ /&entry=(\w+)">/ && $1) {
					# Fetch details of this parent
					if(my $other = $people->fetchrow_hashref({ entry => $xref })) {
						# If the parent has a valid date of birth, format it
						if(my ($year, $month, $day) = parse_date($other->{'dod'})) {
							next if defined($yod) && $year > $yod;

							# Add a "Death of parent" event to the timeline
							add_event(\@events, "Death of $relation", $xref, $other->{'title'}, $year, $month, $day);
						}
					}
				}
			}

			# Process children (if any)
			foreach my $child (split(/----/, $person->{'children'} || '')) {
				if(my $xref = $child =~ /&entry=(\w+)">/ && $1) {
					# Fetch details of this child
					if(my $other = $people->fetchrow_hashref({ entry => $xref })) {
						# If the child has a valid date of birth, format it
						if(my ($year, $month, $day) = parse_date($other->{'dob'})) {
							# Add a "Birth of child" event to the timeline
							add_event(\@events, 'Birth of child', $xref, $other->{'title'}, $year, $month, $day);
						}
						if(my ($year, $month, $day) = parse_date($other->{'dod'})) {
							next if defined($yod) && $year > $yod;
							my $event_type = $language eq 'de' ? 'Todesfall von Kind' :
								$language eq 'fr' ? "Mort d'enfant" :
								'Death of child';
							# Add a "Death of child" event to the timeline
							add_event(\@events, $event_type, $xref, $other->{'title'}, $year, $month, $day);
						}
					}
				}
			}

			# Process spouse
			# TODO: Add support for people married more than once
			if(my $xref = $person->{'bio'} =~ /married <a href=.+?entry=(.+?)">/ && $1) {
				# Fetch details of this spouse
				if(my $spouse = $people->fetchrow_hashref({ entry => $xref })) {
					# If the spouse has a valid date of death, format it
					if(my ($year, $month, $day) = parse_date($spouse->{'dod'})) {
						# Only include on this person's timeline if the spouse died
						#	before they did
						next if defined($yod) && $year > $yod;
						my $event_type = $spouse->{'sex'} eq 'M' ? 'Death of husband' : 'Death of wife';
						# Add a "Death of spouse" event to the timeline
						add_event(\@events, $event_type, $xref, $spouse->{'title'}, $year, $month, $day);
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

# Helper: Parse date into year, month, day, removing leading zeros
sub parse_date
{
	my $date = shift;

	return if(!defined($date));

	if($date =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/) {
		my $year = $1;
		my $month = $2;
		my $day = $3;
		$month =~ s/^0//r;
		$day =~ s/^0//r;
		return ($year, $month, $day);
	}
	return;
}

# Helper: Add an event to the timeline
sub add_event
{
	my ($events, $event_type, $xref, $title, $year, $month, $day) = @_;

	push @$events, {
		event => $event_type,
		person => $xref,
		title => $title,
		year => $year,
		month => $month,
		day => $day,
	};
}

1;
