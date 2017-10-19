package Ged2site::Display::calendar;

use strict;
use warnings;

# Display the calendar page

use Ged2site::Display;
use DateTime;
use DateTime::Locale;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'calendar',
		# 'month' => qr(^\d{1,2}$),	# must be one or two digits
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my $params = $info->params({ allow => $allowed });

	# Handle into the database
	my $history = $args{'history'};

	# if(my $month = $params->{'month'}) {
		# my @events;

		# foreach my $event(@{$history->selectall_hashref({ month => $month })}) {
			# # TODO: sort by name
			# push @{$events[$event->{'day'} - 1]}, $event;
		# }
		# return $self->SUPER::html({
			# events => \@events,
			# month => @{DateTime::Locale->load($self->{_lingua}->language())->month_format_wide()}[$month - 1],
			# year => DateTime->today()->year()
		# });
	# }
	return $self->SUPER::html({
		events => $history->selectall_hashref(),
		updated => $history->updated(),
		year => DateTime->today()->year()
	});
}

1;
