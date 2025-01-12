package Ged2site::Display::history;

# Display the history page

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');
sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		page => 'history',
		entry => undef,	# TODO: Add regex for valid formats
		lang => qr/^[A-Z][A-Z]/i,
		lint_content => qr/^\d$/,
		fbclid => qr/^[\w-]+$/i,	# Facebook tracking info
		gclid => qr/^\w+$/i,	# Google tracking info
	};
	my %params = %{$info->params({ allow => $allowed })};

	my $history = $args{'history'};	# Handle into the database

	# TODO: handle situation where look up fails
        my @events;
	my $template_args = { updated => $history->updated() };
        if(my $entry = $params{'entry'}) {
		# Display the timeline of one person
		# TODO: add items such as birth of children, emigration, world events
                @events = $history->selectall_hash({ person => $entry });
		if(scalar(@events)) {
			$template_args->{'name'} = $events[0]->{'title'};
		}

		my $people = $args{'people'};	# Handle into the database
		if(my $person = $people->fetchrow_hashref({ entry => $entry })) {
			foreach my $relation('mother', 'father') {
				if($person->{$relation} && ($person->{$relation} =~ /&entry=(\w+)">/)) {
					my $xref = $1;
					my $other = $people->fetchrow_hashref({ entry => $xref });
					if($other->{'dod'} && ($other->{'dod'} =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/)) {
						my $year = $1;
						my $month = $2;
						my $day = $3;
						$day =~ s/^0//;
						$month =~ s/^0//;

						push @events, {
							event => "Death of $relation",
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
		# Sort by year
		@events = sort { $a->{'year'} <=> $b->{'year'} } @events;
        } else {
                # Everyone
                @events = $history->selectall_hash();
        }
	
	my $eventshash;	# hash of year to array of events in that year, each event is a hash of the event's details
	foreach my $event(@events) {
		push @{$eventshash->{$event->{'year'}}}, $event;
	}
	$template_args->{'events'} = $eventshash;

	return $self->SUPER::html($template_args);
}

1;
