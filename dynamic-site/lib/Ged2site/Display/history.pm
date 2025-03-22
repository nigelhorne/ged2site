package Ged2site::Display::history;

# Generate HTML for the timeline/history page,
# displaying life events (e.g., births, deaths, marriages, military service),
# whether for a specific individual or across all entries in the database.

use warnings;
use strict;
use Ged2site::Display;
use DateTime::Format::Genealogy;
use Error;
use File::Slurp;
use XML::Simple;

our @ISA = ('Ged2site::Display');

# TODO: This would be much better if it could quickly get to the information in the XML file people.xml
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

		# TODO: handle the situation where a look-up fails
		# TODO: add items such as emigration (need to work out the year), world events
		@events = $history->selectall_hash({ xref => $entry });

		# If events are found, pass the person's name to the template
		# The template uses the [% name %] field to know if it's to display a specific person
		#	or all events in the database
		$template_args->{'name'} = $events[0]->{'title'} if(scalar(@events));

		# Get the people database handle
		my $people = $args{'people'};

		# Fetch person details based on the entry parameter
		if(my $person = $people->fetchrow_hashref({ entry => $entry })) {
			# Get the year of death of the person being displayed
			my ($yod, $mod, $dod) = _parse_date($person->{'dod'});

			# Get the language to display, using these methods:
			#	1: Use the lang parameter given in the URL
			#	2: If that's not set, use CGI::Lingua to interrogate the browser's setting
			#	3: Fall back to English
			my $language = lc($params{'lang'} || $self->{'_lingua'}->language_code_alpha2() || 'en');

			# Process mother and father
			foreach my $relation ('mother', 'father') {
				if(my $parent = $person->{$relation}) {
					if(my $xref = $parent =~ /&amp;entry=(\w+)">/ && $1) {
						# Fetch details of this parent
						if(my $other = $people->fetchrow_hashref({ entry => $xref })) {
							# If the parent has a valid date of birth, format it
							if(my ($year, $month, $day) = _parse_date($other->{'dod'})) {
								next if defined($yod) && $year > $yod;

								# Add a "Death of parent" event to the timeline
								_add_event(\@events, "Death of $relation", $xref, $other->{'title'}, $year, $month, $day);
							}
						}
					}
				}
			}

			if(defined($yod)) {
				# Process children (if any)
				foreach my $child (split(/----/, $person->{'children'} || '')) {
					if(my $xref = $child =~ /&amp;entry=(\w+)">/ && $1) {
						# Fetch details of this child
						if(my $other = $people->fetchrow_hashref({ entry => $xref })) {
							# If the child has a valid date of birth, format it
							if(my ($year, $month, $day) = _parse_date($other->{'dob'})) {
								# Add a "Birth of child" event to the timeline
								_add_event(\@events, 'Birth of child', $xref, $other->{'title'}, $year, $month, $day);
							}
							if(my ($year, $month, $day) = _parse_date($other->{'dod'})) {
								if($year < $yod) {
									my $event_type = $language eq 'de' ? 'Todesfall von Kind' :
										$language eq 'fr' ? "Mort d'enfant" :
										'Death of child';
									# Add a "Death of child" event to the timeline
									_add_event(\@events, $event_type, $xref, $other->{'title'}, $year, $month, $day);
								}
							}
						}
					}
				}

				# Process spouse death information
				# TODO: Add support for people married more than once
				if(my $xref = $person->{'bio'} =~ /married <a href=.+?entry=(.+?)">/ && $1) {
					# Fetch details of this spouse
					if(my $spouse = $people->fetchrow_hashref({ entry => $xref })) {
						# If the spouse has a valid date of death, format it
						if(my ($year, $month, $day) = _parse_date($spouse->{'dod'})) {
							# Only include on this person's timeline if the spouse died
							#	before they did
							if(($year < $yod) ||
							   (($year == $yod) && defined($month) && defined($mod) && ($month < $mod))) {
								my $event_type = ($spouse->{'sex'} eq 'M') ? 'Death of husband' : 'Death of wife';
								# Add a "Death of spouse" event to the timeline
								_add_event(\@events, $event_type, $xref, $spouse->{'title'}, $year, $month, $day);
							}
						}
					}
				}

			}

			# Give the template access to the person's details
			$template_args->{'person'} = _get_person(\%args, \%params);

			# Add the marriages' details - spouse name and date
			if(my $marriages = $template_args->{'person'}->{'marriages'}) {
				if($marriages->{'marriage'}) {
					# Ignore marriage info in the history.csv file; TODO - don't put it in
					@events = grep defined($_), map { $_->{'event'} ne 'Marriage' ? $_ : undef } @events;
					if(ref($marriages->{'marriage'}) eq 'ARRAY') {
						foreach my $marriage(@{$marriages->{'marriage'}}) {
							if(ref($marriage) eq 'HASH') {
								if(my $spouse = $people->fetchrow_hashref({ entry => $marriage->{'spouse'} })) {
									if(my ($year, $month, $day) = _parse_date($marriage->{'date'})) {
										_add_event(\@events, 'Marriage', $marriage->{'spouse'}, $spouse->{'title'}, $year, $month, $day);
									}
								}
							} else {
								throw Error::Simple($template_args->{'person'}->{'xref'} . ": marriage isn't a HASH");
							}
						}
					} else {
						throw Error::Simple($template_args->{'person'}->{'xref'} . ": marriages isn't an ARRAY");
					}
				}
			}
			# Did this person serve in the military?
			if(my $military = $template_args->{'person'}->{'military'}) {
				foreach my $entry($military->{'entry'}) {
					next unless(ref($entry) eq 'HASH');
					my $service = $entry->{'service'} // 'Military';
					if(my $date = $entry->{'date'}) {
						if(ref($date) eq 'HASH') {
							if((my $from = $date->{'from'}) && (my $to = $date->{'to'})) {
								my $dfg = DateTime::Format::Genealogy->new();

								# Add joining military service to the timeline
								if(my ($year, $month, $day) = _parse_date($from)) {
									_add_event(\@events, "Joined the $service", undef, $events[0]->{'title'}, $year, $month, $day);
								} elsif(my $start_dt = $dfg->parse_datetime($from)) {
									_add_event(\@events, "Joined the $service", undef, $events[0]->{'title'}, $start_dt->year(), $start_dt->month(), $start_dt->day());
								} elsif($from =~ /\d{3,4}/) {
									_add_event(\@events, "Joined the $service", undef, $events[0]->{'title'}, $from, undef, undef);
								}
								# Add leaving military service to the timeline
								if(my ($year, $month, $day) = _parse_date($to)) {
									_add_event(\@events, "Left the $service", undef, $events[0]->{'title'}, $year, $month, $day);
								} elsif(my $end_dt = $dfg->parse_datetime($to)) {
									_add_event(\@events, "Left the $service", undef, $events[0]->{'title'}, $end_dt->year(), $end_dt->month(), $end_dt->day());
								} elsif($to =~ /\d{3,4}/) {
									_add_event(\@events, "Left the $service", undef, $events[0]->{'title'}, $to, undef, undef);
								}
							}
						} elsif(!ref($date)) {
                                                        # Add military service to the timeline
							my $dfg = DateTime::Format::Genealogy->new();
                                                        if(my ($year, $month, $day) = _parse_date($date)) {
                                                                _add_event(\@events, "Serving in the $service", undef, $events[0]->{'title'}, $year, $month, $day);
                                                        } elsif(my $end_dt = $dfg->parse_datetime($date)) {
                                                                _add_event(\@events, "Serving in the $service", undef, $events[0]->{'title'}, $end_dt->year(), $end_dt->month(), $end_dt->day());
                                                        } elsif($date =~ /\d{3,4}/) {
                                                                _add_event(\@events, "Serving in the $service", undef, $events[0]->{'title'}, $date, undef, undef);
                                                        }
						} else {
							throw Error::Simple($template_args->{'person'}->{'xref'} . ": military->service->date isn't a HASH");
						}
					}
				}
			} elsif($person->{'bio'} =~ /served in the (.+?) from (.+?) to (.+? \d{4})[\s\.]/) {
				my ($service, $start, $end) = ($1, $2, $3);
				my $dfg = DateTime::Format::Genealogy->new();

				# Add joining military service to the timeline
				if(my $start_dt = $dfg->parse_datetime($start)) {
					_add_event(\@events, "Joined the $service", undef, $events[0]->{'title'}, $start_dt->year(), $start_dt->month(), $start_dt->day());
				}
				# Add leaving military service to the timeline
				if(my $end_dt = $dfg->parse_datetime($end)) {
					_add_event(\@events, "Left the $service", undef, $events[0]->{'title'}, $end_dt->year(), $end_dt->month(), $end_dt->day());
				}
			}
		}

		# Sort events by year in ascending order
		@events = sort {
			if($a->{'month'} && $b->{'month'}) {
				$a->{'year'} == $b->{'year'} ? $a->{'month'} <=> $b->{'month'} : $a->{'day'} <=> $b->{'day'}
			} else {
				$a->{'year'} <=> $b->{'year'}
			}
		} @events;
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
sub _parse_date
{
	my $date = shift;

	return if(!defined($date));

	if($date =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/) {
		my $year = $1;
		my $month = $2;
		my $day = $3;
		$month =~ s/^0//;
		$day =~ s/^0//;
		return ($year, $month, $day);
	}

	if($date =~ /^\d{3,4}$/) {
		return $date;	# Only the year is known
	}
	return;
}

# Helper: Add an event to the timeline
sub _add_event
{
	my ($events, $event_type, $xref, $title, $year, $month, $day) = @_;

	push @{$events}, {
		event => $event_type,
		xref => $xref,
		title => $title,
		year => $year,
		month => $month,
		day => $day
	};
}

# Helper: Get a hashref of the data for this person
sub _get_person
{
	my($args, $params) = @_;

	# Read in the .../data/people/$xref.xml file
	my $xml_string = File::Slurp::read_file(File::Spec->catfile($args->{'database_dir'}, 'people', $params->{'entry'}) . '.xml');

	# Parse the XML string
	if(my $person = XML::Simple->new(ForceArray => 0, KeyAttr => [])->XMLin($xml_string)) {
		return $person->{'person'};
	}
}

1;
