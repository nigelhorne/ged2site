package Ged2site::Display::twins;

# Display the list of twins

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'twins',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};
	return "" if(delete($params{'page'}) ne 'twins');

	my $people = $args{'people'};
	my @all_twins = $args{'twins'}->selectall_hash();
	my @twins;
	my %done;	# Avoid printing the twins twice
	foreach my $twin(@all_twins) {
		next if($done{$twin->{'twin'}});

		push @twins, {
			left => $people->fetchrow_hashref(entry => $twin->{'entry'}),
			right => $people->fetchrow_hashref(entry => $twin->{'twin'}),
		};
		$done{$twin->{'entry'}} = $twin->{'twin'};
	}
	return $self->SUPER::html({ twins => \@twins, updated => $people->updated() });
}

1;
