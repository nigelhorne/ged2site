package Ged2site::Display::graphs;

use strict;
use warnings;
use POSIX;
use DateTime::Locale;
use DateTime::Format::Natural;
use Statistics::LineFit;
use Statistics::Lite;
use HTML::TagCloud;

# Display some information about the family

use Ged2site::Display;

our @ISA = ('Ged2site::Display');

our $BUCKETYEARS = 5;
our $BUCKETDISTANCE = 5;
our $date_parser;
our $dfn;

# TODO: age of people dying vs. year (is that a good idea?)
our $mapper = {
	'ageatdeath' => \&_ageatdeath,
	'birthmonth' => \&_birthmonth,
	'deathmonth' => \&_deathmonth,
	'marriagemonth' => \&_marriagemonth,
	'infantdeaths' => \&_infantdeaths,
	'firstborn' => \&_firstborn,
	'sex' => \&_sex,
	'ageatmarriage' => \&_ageatmarriage,
	'dist' => \&_dist,
	'distcount' => \&_distcount,
	'ageatfirstborn' => \&_ageatfirstborn,
	'familysizetime' => \&_familysizetime,
	'motherchildren' => \&_motherchildren,
	'namecloud' => \&_namecloud,
};

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

	my $updated = $args{'people'}->updated();

	if((!scalar(keys %params)) || !defined($params{'graph'})) {
		# Display the list of graphs
		return $self->SUPER::html(updated => $updated);
	}

	if($mapper->{$params{'graph'}}) {
		my $rc = $mapper->{$params{'graph'}}->($self, \%args);
		$rc->{'updated'} = $updated;
		return $self->SUPER::html($rc);
	}

	return $self->SUPER::html(updated => $updated);
}

# TODO: have separate graphs for male and female
sub _ageatdeath
{
	my $self = shift;
	my $args = shift;

	my $people = $args->{'people'};

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

	my $datapoints;
	my(@x, @y, @samples);

	foreach my $bucket(sort keys %counts) {
		# next if((!defined($datapoints)) && ($counts{$bucket} == 0));
		my $average = $totals{$bucket} / $counts{$bucket};
		$average = floor($average);

		$datapoints .= "{ label: \"$bucket\", y: $average },\n";
		push @x, $bucket;
		push @y, $average;
		push @samples, { bucket => $bucket, size => $counts{$bucket} };
	}
	my $lf = Statistics::LineFit->new();
	if($lf->setData(\@x, \@y)) {
		@y = $lf->predictedYs();
		my $x = shift @x;
		my $y = shift @y;
		my $bestfit = "{ label: \"$x\", y: $y },\n";
		while($x = shift @x) {
			$y = shift @y;
			if($x[0]) {
				$bestfit .= "{ label: \"$x\", y: $y, markerSize: 1 },\n";
			} else {
				$bestfit .= "{ label: \"$x\", y: $y },\n";
			}
		}
		return { mdatapoints => $datapoints, fdatapoints => $bestfit, samples => \@samples };
	}

	return { datapoints => $datapoints, samples => @samples };
}

sub _birthmonth
{
	my $self = shift;
	my $args = shift;

	my $people = $args->{'people'};
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

	my $datapoints;
	my $index = 0;
	my $dtl = DateTime::Locale->load($locale);

	while($index < 12) {
		my $month = @{$dtl->month_format_wide()}[$index];
		$datapoints .= "{ label: \"$month\", y: " . $counts[$index] . " },\n";
		$index++;
	}

	return { datapoints => $datapoints };
}

sub _marriagemonth
{
	my $self = shift;
	my $args = shift;

	my $people = $args->{'people'};
	my @counts = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	foreach my $person(@{$people->selectall_hashref()}) {
		# TODO: Handle more than one marriage
		if(my $dom = $person->{'marriages'}) {
			if($dom =~ /^(.+?)-/) {
				$dom = $1;	# use the first marriage
			}
			if($dom =~ /^\d{3,4}\/(\d{2})\/\d{2}$/) {
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

	my $datapoints;
	my $index = 0;
	my $dtl = DateTime::Locale->load($locale);

	while($index < 12) {
		my $month = @{$dtl->month_format_wide()}[$index];
		$datapoints .= "{ label: \"$month\", y: " . $counts[$index] . " },\n";
		$index++;
	}

	return { datapoints => $datapoints };
}

sub _deathmonth
{
	my $self = shift;
	my $args = shift;

	my $people = $args->{'people'};
	my @counts = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	foreach my $person(@{$people->selectall_hashref()}) {
		if(my $dod = $person->{'dod'}) {
			if($dod =~ /^\d{3,4}\/(\d{2})\/\d{2}$/) {
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

	my $datapoints;
	my $index = 0;
	my $dtl = DateTime::Locale->load($locale);

	while($index < 12) {
		my $month = @{$dtl->month_format_wide()}[$index];
		$datapoints .= "{ label: \"$month\", y: " . $counts[$index] . " },\n";
		$index++;
	}

	return { datapoints => $datapoints };
}

sub _infantdeaths
{
	my $self = shift;
	my $args = shift;

	my %infantdeaths;
	my %totals;
	my $people = $args->{'people'};

	foreach my $person(@{$people->selectall_hashref()}) {
		if($person->{'dob'} && $person->{'dod'}) {
			my $dob = $person->{'dob'};
			my $yob;
			if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
				$dob =~ tr/\//-/;
				$yob = $1;
			} elsif($dob =~ /^\d{3,4}$/) {
				$yob = $dob;
			} else {
				next;
			}
			next if($yob < 1600);
			next if($yob > 2000);
			my $dod = $person->{'dod'};
			my $yod;
			if($dod =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
				$yod = $1;
			} elsif($dod =~ /^\d{3,4}$/) {
				$yod = $dod;
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

	my $datapoints;

	foreach my $bucket(sort keys %totals) {
		if(($totals{$bucket} >= 5) && $infantdeaths{$bucket}) {	# Good data size
			my $percentage = floor(($infantdeaths{$bucket} * 100) / $totals{$bucket});
			$datapoints .= "{ label: \"$bucket\", y: $percentage },\n";
		} elsif(defined($datapoints)) {
			$datapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { datapoints => $datapoints };
}

sub _firstborn
{
	my $self = shift;
	my $args = shift;
	my %months;

	my $people = $args->{'people'};

	$dfn ||= DateTime::Format::Natural->new();
	my $max;
	foreach my $person(@{$people->selectall_hashref()}) {
		if($person->{'children'} && $person->{'marriages'}) {
			my $dom = $person->{'marriages'};
			if($dom =~ /^(.+?)-/) {
				$dom = $1;	# use the first marriage
			}
			my $eldest;
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
					if(defined($eldest)) {
						my $candidate = $self->_date_to_datetime($dob);
						if($candidate < $eldest) {
							$eldest = $candidate;
						}
					} else {
						$eldest = $self->_date_to_datetime($dob);
					}
				}
			}
			if(defined($eldest)) {
				my $d = $eldest->subtract_datetime($self->_date_to_datetime($dom));
				my $months = $d->months() + ($d->years() * 12) - 1;
				$months{$months}++;
				if((!defined($max)) || ($months > $max)) {
					$max = $months;
				}
			}
		}
	}

	my $datapoints;

	foreach my $month(0..$max) {
		if($months{$month}) {
			$datapoints .= "{ label: \"$month\", y: $months{$month} },\n";
		} else {
			$datapoints .= "{ label: \"$month\", y: 0 },\n";
		}
	}

	return { datapoints => $datapoints };
}

sub _sex
{
	my $self = shift;
	my $args = shift;

	my %totals;
	my %mcounts;
	my %fcounts;

	my $people = $args->{'people'};

	foreach my $person(@{$people->selectall_hashref()}) {
		next if($person->{'sex'} !~ /[MF]/);
		next if(!(defined($person->{'dob'})));

		my $dob = $person->{'dob'};
		my $yob;
		if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
			$dob =~ tr/\//-/;
			$yob = $1;
		} elsif($dob =~ /^\d{3,4}$/) {
			$yob = $dob;
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

	return { mdatapoints => $mdatapoints, fdatapoints => $fdatapoints };
}

sub _ageatmarriage
{
	my $self = shift;
	my $args = shift;

	my %mcounts;
	my %mtotals;
	my %fcounts;
	my %ftotals;
	my %mentries;
	my %fentries;

	my $people = $args->{'people'};

	foreach my $person(@{$people->selectall_hashref()}) {
		if($person->{'dob'} && $person->{'marriages'}) {
			my $dob = $person->{'dob'};
			my $yob;
			if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
				$dob =~ tr/\//-/;
				$yob = $1;
			} elsif($dob =~ /^\d{3,4}$/) {
				$yob = $dob;
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
			} elsif($dom =~ /^\d{3,4}$/) {
				$yom = $dom;
			} else {
				next;
			}
			my $age = $yom - $yob;
			$yom -= $yom % $BUCKETYEARS;

			if($person->{'sex'} eq 'M') {
				if($mcounts{$yom}) {
					$mcounts{$yom}++;
					push @{$mentries{$yom}}, $person->{'entry'};
				} else {
					$mcounts{$yom} = 1;
					@{$mentries{$yom}} = ($person->{'entry'});
				}
				if($mtotals{$yom}) {
					$mtotals{$yom} += $age;
				} else {
					$mtotals{$yom} = $age;
				}
			} else {
				if($fcounts{$yom}) {
					$fcounts{$yom}++;
					push @{$fentries{$yom}}, $person->{'entry'};
				} else {
					$fcounts{$yom} = 1;
					@{$fentries{$yom}} = ($person->{'entry'});
				}
				if($ftotals{$yom}) {
					$ftotals{$yom} += $age;
				} else {
					$ftotals{$yom} = $age;
				}
			}
		}
	}

	my $mdatapoints;
	my $fdatapoints;

	foreach my $bucket(keys %mcounts) {
		if(!defined($fcounts{$bucket})) {
			$fcounts{$bucket} = 0;
		}
	}
	foreach my $bucket(keys %fcounts) {
		if(!defined($mcounts{$bucket})) {
			$mcounts{$bucket} = 0;
		}
	}

	foreach my $bucket(sort { $a <=> $b } keys %mcounts) {
		if($mcounts{$bucket}) {
			my $average = floor($mtotals{$bucket} / $mcounts{$bucket});

			my $tooltip = "\"<span style=\\\"color:#F08080\\\">Male (average age {y}, sample size $mcounts{$bucket}):</span> ";
			foreach my $entry(@{$mentries{$bucket}}) {
				my $husband = $people->fetchrow_hashref({ entry => $entry });
				$tooltip .= '<br>' . $husband->{'title'};
			}
			$tooltip .= '"';
			$mdatapoints .= "{ label: \"$bucket\", y: $average, toolTipContent: $tooltip },\n";
		} elsif($mdatapoints) {
			$mdatapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}
	foreach my $bucket(sort { $a <=> $b } keys %fcounts) {
		if($fcounts{$bucket}) {
			my $average = floor($ftotals{$bucket} / $fcounts{$bucket});

			my $tooltip = "\"<span style=\\\"color:#20B2AA\\\">Female (average age {y}, sample size $fcounts{$bucket}):</span> ";
			foreach my $entry(@{$fentries{$bucket}}) {
				my $wife = $people->fetchrow_hashref({ entry => $entry });
				$tooltip .= '<br>' . $wife->{'title'};
			}
			$tooltip .= '"';
			$fdatapoints .= "{ label: \"$bucket\", y: $average, toolTipContent: $tooltip },\n";
		} elsif($fdatapoints) {
			$fdatapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { mdatapoints => $mdatapoints, fdatapoints => $fdatapoints };
}

sub _dist
{
	my $self = shift;
	my $args = shift;

	my $people = $args->{'people'};

	my $units = 'K';

	if($self->{'_lingua'}) {
		if(my $country = $self->{'_lingua'}->country()) {
			if(($country eq 'us') || ($country eq 'uk')) {
				$units = 'M';
			}
		}
	}

	my %totals;
	my %counts;
	my %dists;
	foreach my $person(@{$people->selectall_hashref()}) {
		next unless($person->{'birth_coords'} && $person->{'death_coords'} && $person->{'dob'});
		my $dob = $person->{'dob'};
		my $yob;
		if($dob =~ /^(\d{3,4})/) {
			$yob = $1;
		} else {
			next;
		}
		$yob -= $yob % $BUCKETYEARS;

		my ($blat, $blong) = split(/,/, $person->{'birth_coords'});
		my ($dlat, $dlong) = split(/,/, $person->{'death_coords'});

		$counts{$yob}++;

		if((($blat - $dlat) >= 1e-6) && (($blong - $dlong) >= 1e-6)) {
			my $dist = ::distance($blat, $blong, $dlat, $dlong, $units);
			$totals{$yob} += $dist;
			push @{$dists{$yob}}, $dist;
		} elsif(!defined($totals{$yob})) {
			$totals{$yob} = 0;
			push @{$dists{$yob}}, 0;
		} else {
			push @{$dists{$yob}}, 0;
		}
	}

	my $datapoints;

	foreach my $bucket(sort keys %counts) {
		next if(!defined($counts{$bucket}));
		if($counts{$bucket} >= 10) {
			my $average;
			if(defined($dists{$bucket})) {
				# Dispence with any people who moved more than 3/4 of
				# a standard deviation, since they are likely to bias the
				# data rather heavily.  For example one family of 4
				# who emigrate thousands of miles will have an unduly large
				# effect, especially if the data size is very small
				my %info = Statistics::Lite::statshash(@{$dists{$bucket}});
				# print "$bucket:\n", join(',', @{$dists{$bucket}}), "\n",
					# Statistics::Lite::statsinfo(@{$dists{$bucket}}), "\n";
				my $limit = $info{'mean'} + ($info{'stddev'} * (1 / 4));
				# print "\tLimit: $limit\n";
				my $count;
				my $total;
				foreach my $d(@{$dists{$bucket}}) {
					if($d <= $limit) {
						$count++;
						$total += $d;
						# print "\tAdding $d\n";
					}
				}
				if($count) {
					$average = floor($total / $count);
				}
			} else {
				$average = floor($totals{$bucket} / $counts{$bucket});
			}

			if(defined($average)) {
				$datapoints .= "{ label: \"$bucket\", y: $average },\n";
			} else {
				$datapoints .= "{ label: \"$bucket\", y: 0 },\n";
			}
		} elsif($datapoints) {
			$datapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { datapoints => $datapoints, units => ($units eq 'K') ? 'Kilometres' : 'Miles' };
}

sub _distcount
{
	my $self = shift;
	my $args = shift;

	my $units = 'K';

	if($self->{'_lingua'}) {
		if(my $country = $self->{'_lingua'}->country()) {
			if(($country eq 'us') || ($country eq 'uk')) {
				$units = 'M';
			}
		}
	}

	my $people = $args->{'people'};
	my %counts;
	foreach my $person(@{$people->selectall_hashref()}) {
		next unless($person->{'birth_coords'} && $person->{'death_coords'});
		my $dist;
		if($person->{'birth_coords'} eq $person->{'death_coords'}) {
			$dist = 0;
		} else {
			my ($blat, $blong) = split(/,/, $person->{'birth_coords'});
			my ($dlat, $dlong) = split(/,/, $person->{'death_coords'});

			$dist = floor(::distance($blat, $blong, $dlat, $dlong, $units));
		}
		my $bucket = $dist - ($dist % $BUCKETDISTANCE);
		$counts{$bucket}++;
	}

	my $datapoints;

	foreach my $bucket(sort { $a <=> $b } keys %counts) {
		if($counts{$bucket}) {
			my $count = $counts{$bucket};

			$datapoints .= "{ label: \"$bucket\", y: $count, markerSize: 1 },\n";
		} elsif($datapoints) {
			$datapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { datapoints => $datapoints, units => ($units eq 'K') ? 'Kilometres' : 'Miles' };
}

sub _ageatfirstborn
{
	my $self = shift;
	my $args = shift;
	my %mtotals;
	my %mcounts;
	my %ftotals;
	my %fcounts;

	my $people = $args->{'people'};

	$dfn ||= DateTime::Format::Natural->new();
	foreach my $person(@{$people->selectall_hashref()}) {
		if($person->{'dob'} && $person->{'children'}) {
			my $dob = $person->{'dob'};
			my $yob;
			if($dob =~ /^(\d{3,4})/) {
				$yob = $1;
			} else {
				next;
			}
			my $bucket = $yob - ($yob % $BUCKETYEARS);

			my $firstborn;
			CHILD: foreach my $child(split(/----/, $person->{'children'})) {
				if($child =~ /page=people&entry=([IP]\d+)"/) {
					$child = $people->fetchrow_hashref({ entry => $1 });
					my $cdob = $child->{'dob'};
					next CHILD unless($cdob);
					if($cdob =~ /^(\d{3,4})/) {
						my $cyob = $1;
						if((!defined($firstborn)) || ($cyob < $firstborn)) {
							$firstborn = $cyob;
						}
					}
				}
			}
			if(defined($firstborn)) {
				my $age = $firstborn - $yob;
				if($person->{'sex'} eq 'M') {
					$mtotals{$bucket} += $age;
					$mcounts{$bucket}++;
				} else {
					$ftotals{$bucket} += $age;
					$fcounts{$bucket}++;
				}
			}
		}
	}

	my $mdatapoints;
	my $fdatapoints;

	foreach my $bucket(sort keys %mcounts) {
		if($mcounts{$bucket} >= 5) {
			my $average = ceil($mtotals{$bucket} / $mcounts{$bucket});
			$mdatapoints .= "{ label: \"$bucket\", y: $average },\n";
		} elsif($mdatapoints) {
			$mdatapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}
	foreach my $bucket(sort keys %fcounts) {
		if($fcounts{$bucket} >= 5) {
			my $average = ceil($ftotals{$bucket} / $fcounts{$bucket});
			$fdatapoints .= "{ label: \"$bucket\", y: $average },\n";
		} elsif($fdatapoints) {
			$fdatapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { mdatapoints => $mdatapoints, fdatapoints => $fdatapoints };
}

sub _motherchildren
{
	my $self = shift;
	my $args = shift;

	my %counts;

	my $people = $args->{'people'};

	foreach my $person(@{$people->selectall_hashref({ 'sex' => 'F' })}) {
		if($person->{'children'} && $person->{'dob'}) {
			my $dob = $person->{'dob'};
			if($dob =~ /^(\d{3,4})\/\d{2}\/\d{2}$/) {
				next if($1 < 1820);
			} else {
				next;
			}
			my $count;
			foreach my $child(split(/----/, $person->{'children'})) {
				$count++;
			}
			if($count) {
				$counts{$count}++;
			}
		}
	}

	my $datapoints;

	foreach my $col(sort { $a <=> $b } keys %counts) {
		$datapoints .= "{ label: \"$col\", y: $counts{$col} },\n";
	}

	return { datapoints => $datapoints };
}

sub _familysizetime
{
	my $self = shift;
	my $args = shift;

	my %totals;
	my %counts;

	my $people = $args->{'people'};
	$dfn ||= DateTime::Format::Natural->new();

	foreach my $person(@{$people->selectall_hashref({ 'sex' => 'F' })}) {
		my $count;
		my $eldest;
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
				if(defined($eldest)) {
					my $candidate = $self->_date_to_datetime($dob);
					if($candidate < $eldest) {
						$eldest = $candidate;
					}
				} else {
					$eldest = $self->_date_to_datetime($dob);
				}
				$count++;
			}
		}
		if(defined($eldest)) {
			my $yob = $eldest->year();
			my $bucket = $yob - ($yob % $BUCKETYEARS);
			$totals{$bucket} += $count;
			$counts{$bucket}++;
		}
	}

	my $datapoints;

	foreach my $bucket(sort keys %totals) {
		if($counts{$bucket} >= 5) {
			my $average = $totals{$bucket} / $counts{$bucket};
			$average = floor($average);

			$datapoints .= "{ label: \"$bucket\", y: $average },\n";
		} elsif(defined($datapoints)) {
			$datapoints .= "{ label: \"$bucket\", y: null },\n";
		}
	}

	return { datapoints => $datapoints };
}

sub _namecloud
{
	my $self = shift;
	my $args = shift;

	my %counts;

	my $names = $args->{'names'};

	my $bucket = 60;

	my @rc;

	for(my $bucket = 60; $bucket <= 80; $bucket++) {
		my $all = $names->selectall_hashref({ entry => $bucket });

		use Data::Dumper;
		# print Data::Dumper->new([\$all])->Dump();

		my $cloud = HTML::TagCloud->new();
		foreach my $name(@{$all}) {
			$cloud->add_static($name->{'name'}, $name->{'count'});
		}

		push @rc, { year => $bucket, data => $cloud->html_and_css(50) };
	}

	return { clouds => \@rc };
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
