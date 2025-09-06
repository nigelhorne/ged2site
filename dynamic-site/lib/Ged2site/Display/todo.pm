package Ged2site::Display::todo;

use warnings;
use strict;

# Display the todo page

use Data::Dumper qw(Dumper);

use parent 'Ged2site::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $todo = $args{'todo'};	# Handle into the database
	my $people = $args{'people'};

	# TODO: handle situation where look up fails

	# Create a list of entries in the TODO table, sorted by title
	my @todos = sort { $a->{'title'} cmp $b->{'title'} } @{$todo->selectall_hashref() || []};

	# Now create a list of hashes, each list is a list of entries in the todo table with the same summary field, the earlier
	# sort ensures that the list will be sorted by title
	my $todohash;	# hash of person's name to array of todos for that person, each todo is a hash of the todo's details

	# Ensure only list a person once per summary
	my %seen;
	foreach my $t(@todos) {
		my $key;

		if(exists($t->{'summary'})) {
			$key = $t->{'summary'};
		} elsif(exists($t->{'error'})) {
			$key = $t->{'error'};
		} else {
			$self->{'logger'}->notice('Todo entry missing both summary and error: ' . Dumper($t));
			next;
		}
		next if($seen{$key}{$t->{'title'}}++);
		push @{$todohash->{$key}}, $t;
	}

	# Free memory
	undef %seen;
	undef @todos;

	# print Data::Dumper->new([$todohash])->Dump();
	# return $self->SUPER::html();

	return $self->SUPER::html({ todos => $todohash, updated => $todo->updated() });
}

1;
