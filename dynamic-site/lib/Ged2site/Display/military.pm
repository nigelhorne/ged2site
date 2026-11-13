package Ged2site::Display::military;

# Display the Military Records page

use warnings;
use strict;

use Data::Reuse;
use VWF::Display;

our @ISA = ('VWF::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if(my $military = $args{'military'}) {
		my @military = $military->selectall_hash();

		my $people = $args{'people'} || die;

		# Don't use yet as both tables have a "notes" column
		# use Database::Join;
		# my $xx = Database::Join->new(databases => [ $military, $people ], join_column => 'person', join_map => { 1 => 'entry' });
		# my @xxx = $xx->selectall_hash();
		# use Data::Dumper;
		# print Data::Dumper->new([\$xxx[0]])->Dump();

		# Lookup the full name of the person
		foreach my $person(@military) {
			if(!exists($person->{title})) {
				if(my $title = $people->title(entry => $person->{'person'})) {
					$person->{'title'} = $title;
				}
			}
		}

		@military = sort { $a->{'title'} cmp $b->{'title'} } @military;

		return $self->SUPER::html({ military => \@military, updated => $people->updated() });
	}

	# No military database
	return $self->SUPER::html();
}

1;
