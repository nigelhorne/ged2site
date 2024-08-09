package Ged2site::Display::orphans;

# Display the list of orphans

# The data (orphans.csv) looks like this:
#	entry!xrefs
#	1815!I733,I734,I735

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'orphans',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};
	return "" if(delete($params{'page'}) ne 'orphans');

	my $people = $args{'people'};
	my @all_orphans = $args{'orphans'}->selectall_hash();	# Slurp in the entire table
	my @years;
	foreach my $orphan(@all_orphans) {
		push @years, {
			year => $orphan->{'entry'},
			orphans => [ map {
				$people->fetchrow_hashref(entry => $_)
			} split(/,/, $orphan->{'xrefs'}) ]
		};
	}
	return $self->SUPER::html({ years => \@years, updated => $people->updated() });
}

1;
