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
        if(my $entry = $params{'entry'}) {
		# Display the timeline of one person
		# TODO: add items such as birth of children, emigration, death of parents
                @events = $history->selectall_hash({ person => $entry });
        } else {
                # Everyone
                @events = $history->selectall_hash();
        }
	
	my $eventshash;	# hash of year to array of events in that year, each event is a hash of the event's details
	foreach my $event(@events) {
		push @{$eventshash->{$event->{'year'}}}, $event;
	}

	return $self->SUPER::html({ events => $eventshash, updated => $history->updated() });
}

1;
