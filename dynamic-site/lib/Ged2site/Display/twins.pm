package Ged2site::Display::twins;

# Display the twins in the database

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'twins',
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my %params = %{$info->params({ allow => $allowed })};
	delete $params{'page'};

	# Handle into the database
	my $people = $args{'people'};

	my $query = 'SELECT DISTINCT p1.* FROM people p1, people p2 WHERE (p1.dob IS NOT NULL) AND (p1.dob <> "") AND (p1.dob = p2.dob) AND (p1.mother = p2.mother) AND (p1.title <> p2.title) AND (p1.alive = 0)';

	my @twins = sort { $a->{'title'} cmp $b->{'title'} } @{$people->execute(query => $query)};

	return $self->SUPER::html({ twins => \@twins, updated => $people->updated() });
}

1;
