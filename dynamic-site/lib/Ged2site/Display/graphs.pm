package Ged2site::Display::graphs;

# Other ideas - age at first marriage (two lines M&F) vs. year of birth
# Distance between birth&death places vs. year of birth
# Time (in months) between frst marriage and first child

use strict;
use warnings;
use POSIX;

# Display some information about the family

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

our $AGEATDEATHBUCKETYEARS = 5;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'graphs',
		'graph' => qr/^[a-z]+$/,
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my %params = %{$info->params({ allow => $allowed })};

	my $people = $args{'people'};

	if((!scalar(keys %params)) || !defined($params{'graph'})) {
		# Display the main index page
		return $self->SUPER::html(updated => $people->updated());
	}

	if($params{'graph'} eq 'ageatdeath') {
		my %counts;
		my %totals;

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
				next if($yob < 1840);
				next if($yob >= 1930);
				my $dod = $person->{'dod'};
				my $yod;
				if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$yod = $1;
				} else {
					next;
				}
				my $age = $yod - $yob;
				next if ($age < 20);
				$yob -= $yob % $AGEATDEATHBUCKETYEARS;
				if($counts{$yob}) {
					$counts{$yob}++;
					$totals{$yob} += $yod - $yob;
				} else {
					$counts{$yob} = 1;
					$totals{$yob} = $yod - $yob;
				}
			}
		}

		my $datapoints;
		
		foreach my $bucket(sort keys %counts) {
			# next if((!defined($datapoints)) && ($counts{$bucket} == 0));
			my $average = $totals{$bucket} / $counts{$bucket};
			$average = floor($average);
			
			$datapoints .= "{ label: \"$bucket\", y: $average },\n";
		}

		return $self->SUPER::html({
			datapoints => $datapoints,
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
	} elsif($params{'graph'} eq 'infantdeaths') {
		my %infantdeaths;
		my %totals;

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
				next if($yob < 1600);
				next if($yob > 2000);
				my $dod = $person->{'dod'};
				my $yod;
				if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$yod = $1;
				} else {
					next;
				}
				my $age = $yod - $yob;
				$yob -= $yob % $AGEATDEATHBUCKETYEARS;

				if($totals{$yob}) {
					$totals{$yob}++;
				} else {
					$totals{$yob} = 1;
				}
				if($age <= 5) {
					if($infantdeaths{$yob}) {
						$infantdeaths{$yob}++;
					} else {
						$infantdeaths{$yob} = 1;
					}
				}
			}
		}

		my $datapoints;
		
		foreach my $bucket(sort keys %totals) {
			if($infantdeaths{$bucket}) {
				my $percentage = floor(($infantdeaths{$bucket} * 100) / $totals{$bucket});
				$datapoints .= "{ label: \"$bucket\", y: $percentage },\n";
			}
		}

		return $self->SUPER::html({
			datapoints => $datapoints,
			updated => $people->updated()
		});
	}
}

1;
