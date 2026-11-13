package Ged2site::Display::military;

# Display the Military Records page

use warnings;
use strict;

use Database::Join;
use Params::Get;
use Web::VWF::Display;

our @ISA = ('Web::VWF::Display');

sub html {
	my $self = shift;
	my $args = Params::Get::get_params(undef, \@_);

	if(my $military = $args->{'military'}) {
		my $people = $args->{'people'} || die;
		my $joined = Database::Join->new(databases => [ $military, $people ], join_column => 'person', join_map => { 1 => 'entry' }, collision_prefix => { 1 => 'people' });
		if(my $all = $joined->selectall_arrayref()) {
			$all = [ sort { $a->{'title'} cmp $b->{'title'} } @{$all} ];

			return $self->SUPER::html({ military => $all, updated => $people->updated() });
		}
	}

	# No military database
	return $self->SUPER::html();
}

1;
