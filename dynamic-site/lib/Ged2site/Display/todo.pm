package Ged2site::Display::todo;

# Display the todo page

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $todohash;	# hash of person's name to array of todos for that person, each todo is a hash of the todo's details

	my $todo = $args{'todo'};	# Handle into the database
	my $people = $args{'people'};

	# TODO: handle situation where look up fails

	my $todos = $todo->selectall_hashref();
	foreach my $t(@{$todos}) {
		push @{$todohash->{$t->{'error'}}}, $t;
	}

	# use Data::Dumper;
	# print Data::Dumper->new([$todohash])->Dump();
	# return $self->SUPER::html();

	return $self->SUPER::html({ todos => $todohash, updated => $todo->updated() });
}

1;
