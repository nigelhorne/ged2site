package Ged2site::Display::surnames;

# Display the surnames page

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'surnames',
		'surname' => qr/[A-Z\s]+/i,
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my %params = %{$self->{_info}->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lang'};

	# Handles into the databases
	my $surnames = $args{'surnames'};
	my $people = $args{'people'};

	unless(scalar(keys %params)) {
		# Display the main index page
		my @s = $surnames->surname();
		return $self->SUPER::html({ surnames => \@s, updated => $surnames->updated() });
	}

	# Look in the surnames.csv for the name given as the CGI argument and
	# find their details
	my $surname = $surnames->selectall_hashref(\%params);
	my @people = map { $people->fetchrow_hashref({ entry => $_->{'person'} }) } @{$surname};

	# TODO: handle situation where look up fails
	return $self->SUPER::html({ people => \@people, updated => $surnames->updated() });
}

1;
