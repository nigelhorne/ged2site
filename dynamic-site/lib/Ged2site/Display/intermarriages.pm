package Ged2site::Display::intermarriages;

# Display the list of intermarriages

use warnings;
use strict;
use Ged2site::Display;

use parent 'Ged2site::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'intermarriages',
		'lang' => qr/^[A-Za-z]{2}$/,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$self->{'_info'}->params({ allow => $allowed })};

	my $people = $args{'people'};
	my @all_intermarriages = $args{'intermarriages'}->selectall_hash();
	my @intermarriages;
	my %done;	# Avoid printing the intermarriages twice
	foreach my $intermarriage(@all_intermarriages) {
		# entry!spouse!relationship
		next if($done{$intermarriage->{'spouse'}});

		push @intermarriages, {
			left => $people->fetchrow_hashref(entry => $intermarriage->{'entry'}),
			right => $people->fetchrow_hashref(entry => $intermarriage->{'spouse'}),
			intermarriage => $intermarriage,
		};
		$done{$intermarriage->{'entry'}} = $intermarriage->{'spouse'};
	}
	return $self->SUPER::html({ intermarriages => \@intermarriages, updated => $args{'intermarriages'}->updated() });
}

1;
