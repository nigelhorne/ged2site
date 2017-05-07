package Ged2site::Display::graphs;

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
				next if($yob >= 1940);
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
		
		foreach my $decade(sort keys %counts) {
			next if((!defined($datapoints)) && ($counts{$decade} == 0));
			my $average;
			if($counts{$decade}) {
				$average = $totals{$decade} / $counts{$decade};
				$average = floor($average);
			} else {
				$average = 0;
			}
			
			$datapoints .= "{ label: \"$decade\", y: $average },\n";
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
	}
}

1;
