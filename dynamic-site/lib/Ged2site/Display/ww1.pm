package Ged2site::Display::ww1;

# Display the First World War page

use warnings;
use strict;
use Ged2site::Display;
use Locale::Country;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'ww1',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};

	delete $params{'page'};
	delete $params{'lint_content'};
	delete $params{'lang'};

	# Handle into the database
	my $people = $args{'people'};

	my @everyone = $people->selectall_hash(\%params);

	my @wardead;

	foreach my $person(@everyone) {
		next if(!exists($person->{'dod'}));
		next if(!defined($person->{'dod'}));
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

		my $dcountry = $person->{'death_country'};
		if(!defined($dcountry)) {
			if($person->{'bio'} =~ /In (\d{4}) s?he was serving in the military/i) {
				next if(($1 < 1914) || ($1 > 1918));
				# Died in an unknown country while serving in the military during the First World War
				push @wardead, $person;
			}
			next;
		}
		if(length($dcountry) > 2) {
			$dcountry = lc(country2code($dcountry));
		}

		if(($dcountry eq 'be') || ($dcountry eq 'fr') || ($dcountry eq 'nl') || ($dcountry eq 'de') || ($dcountry eq 'it')) {
			push @wardead, $person;
		}
	}

	@wardead = sort { $a->{'title'} cmp $b->{'title'} } @wardead;

	return $self->SUPER::html({ wardead => \@wardead, updated => $people->updated() });
}

1;
