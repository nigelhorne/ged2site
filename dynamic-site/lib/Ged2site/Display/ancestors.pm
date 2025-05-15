package Ged2site::Display::ancestors;

use strict;
use warnings;

# Display the ancestors page

use File::Slurp;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'ancestors',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my $params = $info->params({ allow => $allowed });

	my $ancestors = read_file(File::Spec->catfile($args{'database_dir'}, '/people.json'), scalar_ref => 1);

	# FIXME: work out how to pass in a ref to the TT.  It gives an error in Template::Stash::XS when attempting to deref a pointer to a scalar
	return $self->SUPER::html({ ancestors => $$ancestors });
}

1;
