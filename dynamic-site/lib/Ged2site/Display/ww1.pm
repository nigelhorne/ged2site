package Ged2site::Display::ww1;

# Display the First World War page
# FIXME:  This is slow because of the reverse_geocode calls.  Would be better to use the original
#	data, but that can't always be trusted to be of normalised form.  Need to find a way of
#	speeding this up.

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');
our $geocoder;
our %cache;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'ww1',
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my %params = %{$info->params({ allow => $allowed })};
	delete $params{'page'};

	# Handle into the database
	my $people = $args{'people'};

	my $everyone = $people->selectall_hashref(\%params);

	my @wardead;

	foreach my $person(@{$everyone}) {
		next unless($person->{'dod'});
		my $dod = $person->{'dod'};
		my $yod;
		if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
			$dod =~ tr/\//-/;
			$yod = $1;
		} elsif($dod =~ /^\d{3,4}$/) {
			$yod = $dod;
		} else {
			next;
		}
		next if($yod < 1914);
		next if($yod > 1918);

		next unless($person->{'death_country'});
		my $dcountry = $person->{'death_country'};
		next unless(($dcountry eq 'be') || ($dcountry eq 'fr') || ($dountry eq 'nl'));

		push @wardead, $person;
	}

	@wardead = sort { $a->{'title'} cmp $b->{'title'} } @wardead;

	return $self->SUPER::html({ wardead => \@wardead, updated => $people->updated() });
}

1;
