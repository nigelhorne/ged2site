package Ged2site::Display::surnames;

# Display the surnames page

use Ged2site::Display;
use HTML::Entities;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'surnames',
		'surname' => qr/[A-Z\s]+/i,
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/
	};
	my %params = %{$self->{_info}->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	# Handles into the databases
	my $surnames = $args{'surnames'};
	my $people = $args{'people'};

	unless(scalar(keys %params)) {
		# Display the list of surnames
		my @s = map {
			HTML::Entities::decode($_)
		} $surnames->surname(distinct => 1);
		return $self->SUPER::html({ surnames => \@s, updated => $surnames->updated() });
	}

	# Look in the surnames.csv for the name given as the CGI argument and
	# find their details
	my @people = map { $people->fetchrow_hashref({ entry => $_->{'person'} }) } $surnames->selectall_hash(\%params);

	# If there's only one match, go straight to that person
	# For this to work, it would have to be called in the http() routine, not the html() routine
	# if(scalar(@people) == 1) {
		# my $script_name = $self->{_info}->script_name();
		# my $entry = $people[0]->{'entry'};
		# return "Location: $script_name?page=people&entry=$entry\n\n";
	# }

	@people = sort { $a->{'title'} cmp $b->{'title'} } @people;

	# TODO: handle situation where look up fails
	return $self->SUPER::html({ people => \@people, updated => $surnames->updated() });
}

1;
