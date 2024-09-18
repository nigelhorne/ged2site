package Ged2site::Display::changes;

# Display changes template file

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'changes',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};
	return "" if(delete($params{'page'}) ne 'changes');

	my $people = $args{'people'};
	my @changes = $args{'changes'}->selectall_hash();

	foreach my $change(@changes) {
		# Retrieve the person entry for this entry in the change table
		#	and make it available to the template
		# FIXME: this can take some time
		$change->{'person'} = $people->fetchrow_hashref(entry => $change->{'xref'});
	}
	return $self->SUPER::html({ changes => \@changes, updated => $args{'changes'}->updated() });
}

1;
