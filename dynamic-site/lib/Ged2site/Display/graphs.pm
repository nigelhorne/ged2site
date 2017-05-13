package Ged2site::Display::graphs;

# Other ideas:
#	Distance between birth&death places vs. year of birth

use strict;
use warnings;
use POSIX;
use DateTime::Locale;
use DateTime::Format::Natural;

# Display some information about the family

use Ged2site::Display::page;

our @ISA = ('Ged2site::Display::page');

our $BUCKETYEARS = 5;
our $date_parser;
our $dfn;

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
		# Display the list of graphs
		return $self->SUPER::html(updated => $people->updated());
	}

	my $datapoints;
		
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
				$yob -= $yob % $BUCKETYEARS;
				if($counts{$yob}) {
					$counts{$yob}++;
					$totals{$yob} += $yod - $yob;
				} else {
					$counts{$yob} = 1;
					$totals{$yob} = $yod - $yob;
				}
			}
		}

		foreach my $bucket(sort keys %counts) {
			# next if((!defined($datapoints)) && ($counts{$bucket} == 0));
			my $average = $totals{$bucket} / $counts{$bucket};
			$average = floor($average);
			
			$datapoints .= "{ label: \"$bucket\", y: $average },\n";
		}
	} elsif($params{'graph'} eq 'birthmonth') {
		my @counts = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
		foreach my $person(@{$people->selectall_hashref()}) {
			if(my $dob = $person->{'dob'}) {
				if($dob =~ /^\d{3,4}\/(\d{2})\/\d{2}$/) {
					$counts[$1 - 1]++;
				}
			}
		}

		my $locale;
		if($self->{'_lingua'}) {
			if(my $language = $self->{'_lingua'}->language_code_alpha2()) {
				$locale = $language;
			}
		}
		if(!defined($locale)) {
			$locale = 'en';
		}
		my $dtl = DateTime::Locale->load($locale);

		my $index = 0;
		while($index < 12) {
			my $month = @{$dtl->month_format_wide()}[$index];
			$datapoints .= "{ label: \"$month\", y: " . $counts[$index] . " },\n";
			$index++;
		}
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
				$yob -= $yob % $BUCKETYEARS;

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

		foreach my $bucket(sort keys %totals) {
			if(($totals{$bucket} >= 5) && $infantdeaths{$bucket}) {	# Good data size
				my $percentage = floor(($infantdeaths{$bucket} * 100) / $totals{$bucket});
				$datapoints .= "{ label: \"$bucket\", y: $percentage },\n";
			} elsif(defined($datapoints)) {
				$datapoints .= "{ label: \"$bucket\", y: null },\n";
			}
		}
	} elsif($params{'graph'} eq 'firstborn') {
		my %months;

		$dfn ||= DateTime::Format::Natural->new();
		my $max;
		foreach my $person(@{$people->selectall_hashref()}) {
			if($person->{'children'} && $person->{'marriages'}) {
				my $dom = $person->{'marriages'};
				if($dom =~ /^(.+?)-/) {
					$dom = $1;	# use the first marriage
				}
				my $youngest;
				CHILD: foreach my $child(split(/----/, $person->{'children'})) {
					if($child =~ /page=people&entry=([IP]\d+)"/) {
						$child = $people->fetchrow_hashref({ entry => $1 });
						my $dob = $child->{'dob'};
						next CHILD unless($dob);
						if($dob =~ /^(\d{3,4})\/(\d{2})\/(\d{2})$/) {
							$dob = "$3/$2/$1";
						} else {
							next CHILD;
						}
						if(defined($youngest)) {
							my $candidate = $self->_date_to_datetime($dob);
							if($candidate < $youngest) {
								$youngest = $candidate;
							}
						} else {
							$youngest = $self->_date_to_datetime($dob);
						}
					}
				}
				if(defined($youngest)) {
					my $d = $youngest->subtract_datetime($self->_date_to_datetime($dom));
					my $months = $d->months() + ($d->years() * 12) - 1;
					$months{$months}++;
					if((!defined($max)) || ($months > $max)) {
						$max = $months;
					}
				}
			}
		}

		foreach my $month(0..$max) {
			if($months{$month}) {
				$datapoints .= "{ label: \"$month\", y: $months{$month} },\n";
			} else {
				$datapoints .= "{ label: \"$month\", y: 0 },\n";
			}
		}
	} elsif($params{'graph'} eq 'sex') {
		my %totals;
		my %mcounts;
		my %fcounts;

		foreach my $person(@{$people->selectall_hashref()}) {
			next if($person->{'sex'} !~ /[MF]/);
			next if(!(defined($person->{'dob'})));

			my $dob = $person->{'dob'};
			my $yob;
			if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
				$dob =~ tr/\//-/;
				$yob = $1;
			} else {
				next;
			}
			$yob -= $yob % $BUCKETYEARS;

			if($person->{'sex'} eq 'M') {
				if($mcounts{$yob}) {
					$mcounts{$yob}++;
				} else {
					$mcounts{$yob} = 1;
				}
			} else {
				if($fcounts{$yob}) {
					$fcounts{$yob}++;
				} else {
					$fcounts{$yob} = 1;
				}
			}
			if($totals{$yob}) {
				$totals{$yob}++;
			} else {
				$totals{$yob} = 1;
			}
		}


		my $mdatapoints;
		my $fdatapoints;

		foreach my $bucket(sort keys %totals) {
			if(($totals{$bucket} >= 25) && defined($fcounts{$bucket}) && defined($mcounts{$bucket})) {
				my $percentage = $mcounts{$bucket} * 100 / $totals{$bucket};
				$mdatapoints .= "{ label: \"$bucket\", y: $percentage },\n";

				$percentage = $fcounts{$bucket} * 100 / $totals{$bucket};
				$fdatapoints .= "{ label: \"$bucket\", y: $percentage },\n";
			} elsif(defined($mdatapoints)) {
				$mdatapoints .= "{ label: \"$bucket\", y: null },\n";
				$fdatapoints .= "{ label: \"$bucket\", y: null },\n";
			}
		}

		return $self->SUPER::html({
			mdatapoints => $mdatapoints,
			fdatapoints => $fdatapoints,
			updated => $people->updated()
		});
	} elsif($params{'graph'} eq 'ageatmarriage') {
		my %mcounts;
		my %mtotals;
		my %fcounts;
		my %ftotals;

		foreach my $person(@{$people->selectall_hashref()}) {
			if($person->{'dob'} && $person->{'marriages'}) {
				my $dob = $person->{'dob'};
				my $yob;
				if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$dob =~ tr/\//-/;
					$yob = $1;
				} else {
					next;
				}
				next if($yob < 1600);
				my $dom = $person->{'marriages'};
				if($dom =~ /^(.+?)-/) {
					$dom = $1;	# use the first marriage
				}
				my $yom;
				if($dom =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
					$yom = $1;
				} else {
					next;
				}
				my $age = $yom - $yob;
				$yob -= $yob % $BUCKETYEARS;

				if($person->{'sex'} eq 'M') {
					if($mcounts{$yob}) {
						$mcounts{$yob}++;
					} else {
						$mcounts{$yob} = 1;
					}
					if($mtotals{$yob}) {
						$mtotals{$yob} += $age;
					} else {
						$mtotals{$yob} = $age;
					}
				} else {
					if($fcounts{$yob}) {
						$fcounts{$yob}++;
					} else {
						$fcounts{$yob} = 1;
					}
					if($ftotals{$yob}) {
						$ftotals{$yob} += $age;
					} else {
						$ftotals{$yob} = $age;
					}
				}
			}
		}

		my $mdatapoints;
		my $fdatapoints;

		foreach my $bucket(sort keys %mcounts) {
			next if(!defined($fcounts{$bucket}));

			my $average = $mtotals{$bucket} / $mcounts{$bucket};
			$average = floor($average);
			
			$mdatapoints .= "{ label: \"$bucket\", y: $average },\n";

			$average = $ftotals{$bucket} / $fcounts{$bucket};
			$average = floor($average);
			
			$fdatapoints .= "{ label: \"$bucket\", y: $average },\n";
		}

		return $self->SUPER::html({
			mdatapoints => $mdatapoints,
			fdatapoints => $fdatapoints,
			updated => $people->updated()
		});
	}

	return $self->SUPER::html({
		datapoints => $datapoints,
		updated => $people->updated()
	});
}

sub _date_to_datetime
{
	my $self = shift;
	my %params;
	
	if(ref($_[0]) eq 'HASH') {
		%params = %{$_[0]};
	} elsif(scalar(@_) % 2 == 0) {
		%params = @_;
	} else {
		$params{'date'} = shift;
	}

	return $dfn->parse_datetime(string => $params{'date'});
}

1;
