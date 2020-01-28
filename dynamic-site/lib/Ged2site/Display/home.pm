package Ged2site::Display::home;

use warnings;
use strict;

# Display the home page - list today's events
# TODO: More than just BMD, for example baptisms and travelling
# FIXME: The date is the UTC rather than in the correct timezone of the
#	client browser

use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	die unless($info);

	my $allowed = {
		'page' => 'home',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	my $history = $args{'history'};
	my $today = DateTime->today();
	my $events = $history->selectall_hashref({
		day => $today->day(),
		month => $today->month()
	});

	my @e = sort { $a->{'year'} <=> $b->{'year'} } values @{$events};

	return $self->SUPER::html(
		events => \@e,
		updated => $history->updated()
	);
}

1;
