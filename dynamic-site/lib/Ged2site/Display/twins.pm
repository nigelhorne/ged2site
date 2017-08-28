package Ged2site::Display::twins;

# Display the twins in the database
# FIXME:  Don't include living people

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

	# TODO: work out to include common mother
	# FIXME: only prints one of the twins
	my $query = 'SELECT * FROM people GROUP BY dob HAVING (count(dob) > 1)';
	my @twins = @{$people->execute(query => $query)};

	@twins = sort { $a->{'title'} cmp $b->{'title'} } @twins;

	return $self->SUPER::html({ twins => \@twins, updated => $people->updated() });
}

1;
