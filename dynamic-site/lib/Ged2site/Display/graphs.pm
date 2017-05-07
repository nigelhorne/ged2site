package Ged2site::Display::graphs;

use strict;
use warnings;

# Display some information about the family

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'graphs',
		'graph' => qr/^[A-Z][A-Z]/i,
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my %params = %{$info->params({ allow => $allowed })};

	my $people = $args{'people'};

	if((!scalar(keys %params)) || !defined($params{'graph'})) {
		# Display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	if($params{'graph'} eq 'ageatdeath') {
		my $items;
		my $start;
		my $end;

		foreach my $person(@{$people->selectall_hashref()}) {
			if($person->{'dob'} && $person->{'dod'}) {
				my $dob = $person->{'dob'};
				my $yob;
				if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$dob =~ tr/\//-/;
					$yob = $1;
				} else {
					next;
				}
				my $dod = $person->{'dod'};
				my $yod;
				if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$yod = $1;
				} else {
					next;
				}
				my $age = $yod - $yob;
				$items .= "{x: '$dob', y: $age},\n";
				if((!defined($start)) || ($yob < $start)) {
					$start = $yob;
				}
				if((!defined($end)) || ($yod > $end)) {
					$end = $yod;
				}
			}
		}
			
		# drawpoints: false,
		# interpolation: {
		#	parametrization: 'centripetal'
		# },
		my $options = "start: '$start-01-01',\nend: '$end-12-31'\n";

		return $self->SUPER::html({
			items => $items,
			options => $options,
			updated => $people->updated()
		});
	} elsif($params{'graph'} eq 'birthmonth') {
		my @counts = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
		foreach my $person(@{$people->selectall_hashref()}) {
			if(my $dob = $person->{'dob'}) {
				if($dob =~ /^\d{3,4}\/(\d{2})\/\d{2}$/) {
					$counts[$1 - 1]++;
				}
			}
		}

		my $datapoints;
		my $index = 0;
		my $dtl = DateTime::Locale->load($self->{'_lingua'}->language_code_alpha2());
		while($index < 12) {
			my $month = @{$dtl->month_format_wide()}[$index];
			$datapoints .= "{ label: \"$month\", y: " . $counts[$index] . " },\n";
			$index++;
		}

		return $self->SUPER::html({
			datapoints => $datapoints,
			updated => $people->updated()
		});
	}
}

1;
