package Ged2site::Display::emmigrants;

# Display the emmigrants page

use Ged2site::Display::page;
use Geo::Coder::OSM;

our @ISA = ('Ged2site::Display::page');
our $geocoder;
our %cache;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'emmigrants',
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my $params = $info->params({ allow => $allowed });
	if($params && $params->{'page'}) {
		delete $params->{'page'};
	}

	# Handles into the database
	my $people = $args{'people'};

	# Look in the people.csv for the name given as the CGI argument and
	# find their details
print STDERR "000000000\n";
	my $everyone = $people->selectall_hashref($params);

print STDERR "11111111\n";
	$geocoder ||= Geo::Coder::OSM->new();
print STDERR "222222222\n";

	my @emmigrants;

	foreach my $person(@{$everyone}) {
print STDERR $person->{'title'}, "\n";
print STDERR $person->{'birth_coords'}, "\n";
		next unless($person->{'birth_coords'} && $person->{'death_coords'});
		next if($person->{'birth_coords'} eq $person->{'death_coords'});

		my $birth = $cache{$person->{'birth_coords'}};
print STDERR 'b', $person->{'birth_coords'}, "\n";
		if(!defined($birth)) {
			$birth = $geocoder->reverse_geocode(latlng => $person->{'birth_coords'});
			$cache{$person->{'birth_coords'}} = $birth;
		}
		die unless($birth);
		next unless($birth);

		my $death = $cache{$person->{'death_coords'}};
print STDERR 'd', $person->{'death_coords'}, "\n";
		if(!defined($death)) {
			$death = $geocoder->reverse_geocode(latlng => $person->{'death_coords'});
			$cache{$person->{'death_coords'}} = $death;
		}
		next unless($death);

print STDERR "Compare $birth->{address}{country} with $death->{address}{country}\n";
		if($birth->{'address'}{'country'} ne $death->{'address'}{'country'}) {
			push @emmigrants, $person;
		}
	}

	# TODO: handle situation where look up fails
	return $self->SUPER::html({ emmigrants => \@emmigrants, updated => $people->updated() });
}

1;
