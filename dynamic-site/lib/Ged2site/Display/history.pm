package Ged2site::Display::history;

# Display the history page

use Ged2site::Display::page;
use MIME::Base64;

our @ISA = ('Ged2site::Display::page');
sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $eventshash;	# hash of year to array of events in that year, each event is a hash of the event's details

	my $history = $args{'history'};	# Handle into the database
	my $people = $args{'people'};

	# TODO: handle situation where look up fails

	my $events = $history->selectall_hashref();
	foreach my $event(@{$events}) {
		push @{$eventshash->{$event->{'year'}}}, $event;
	}

	return $self->SUPER::html({ events => $eventshash });
}

1;
