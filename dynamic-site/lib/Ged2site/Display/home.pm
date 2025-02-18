package Ged2site::Display::home;

use warnings;
use strict;

# Display the home page - list today's events
# TODO: More than just BMD, for example baptisms and travelling

use Ged2site::Display;
use DateTime;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $logger = $self->{'_logger'};
	if($logger) {
		$logger->trace(__PACKAGE__, ': entering html()');
	}

	my $info = $self->{_info};
	die unless($info);

	my $allowed = {
		'page' => 'home',
		lang => qr/^[A-Z]{2}$/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};

	my $history = $args{'history'};
	my $today = DateTime->today(time_zone => $self->{_lingua}->time_zone());
	my $events = $history->selectall_hashref({
		day => $today->day(),
		month => $today->month()
	});

	# Get the people database handle
	my $people = $args{'people'};

	foreach my $event(@{$events}) {
		# Fetch person details based on the entry parameter
		$event->{'person'} = $people->fetchrow_hashref({ entry => $event->{'xref'} });
	}

	# Sort in chronological order (we only care about the year)
	my @e = sort { $a->{'year'} <=> $b->{'year'} } values @{$events};

	return $self->SUPER::html(
		events => \@e,
		updated => $history->updated()
	);
}

1;
