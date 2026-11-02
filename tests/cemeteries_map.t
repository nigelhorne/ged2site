#!/usr/bin/env perl

# Tests for the map on the dynamic site's cemeteries page:
#
#   cemetery_location() in ged2site must not believe a geocoder that places a
#	cemetery far from its town.  "St Peter's Churchyard, Ramsgate, Kent, England"
#	was placed in Illinois.
#
#   _cemetery_map() must give each location one marker, since only the top one of
#	several markers in the same place can be clicked, and must link to the people.
#
#   VWF::Display's Content-Security-Policy must allow what HTML::OSM loads.
#	Without that the browser silently leaves the map blank, and upgrading
#	HTML::OSM to a different version of Leaflet would do just that.
#
# None of this needs the network or a generated site

use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
	plan(skip_all => 'HTML::OSM needed') unless(eval { require HTML::OSM; 1 });
	plan(skip_all => 'GIS::Distance needed') unless(eval { require GIS::Distance; require Geo::Location::Point; 1 });
	plan(skip_all => 'VWF::Display needs modules that are not installed')
		unless(eval { unshift @INC, "$FindBin::Bin/../dynamic-site/lib"; require Ged2site::Display::cemeteries; 1 });
}

my $root = "$FindBin::Bin/..";

sub slurp
{
	my $file = shift;

	open(my $in, '<:encoding(UTF-8)', $file) or BAIL_OUT("$file: $!");
	local $/;
	my $rc = <$in>;
	close $in;
	return $rc;
}

subtest 'cemetery_location' => sub {
	# ged2site can't be loaded as a module, so take the routine out of it
	my ($source) = slurp("$root/ged2site") =~ /^(sub cemetery_location\n\{.+?^\})/ms;
	ok(defined($source), 'found cemetery_location() in ged2site') or return;

	my %places;
	no warnings 'once';
	*main::get_location = sub { return $places{$_[0]} };
	*main::CEMETERY_MAX_KM_FROM_TOWN = sub () { 50 };
	eval "$source; 1" or BAIL_OUT($@);

	my $point = sub { return Geo::Location::Point->new(lat => $_[0], long => $_[1]) };
	my $ramsgate = $point->(51.33, 1.41);

	%places = (
		'Ramsgate, Kent, England' => $ramsgate,
		"St Peter's Churchyard, Ramsgate, Kent, England" => $point->(51.34, 1.42),
	);
	is(cemetery_location("St Peter's Churchyard, Ramsgate, Kent, England")->lat(), 51.34,
		'a cemetery found close to its town is used');

	$places{"St Peter's Churchyard, Ramsgate, Kent, England"} = $point->(38.7, -89.97);
	is(cemetery_location("St Peter's Churchyard, Ramsgate, Kent, England")->lat(), 51.33,
		'a cemetery found far from its town is replaced by the town');

	%places = ('Ramsgate, Kent, England' => $ramsgate);
	is(cemetery_location('Unknown Cemetery, Some Road, Ramsgate, Kent, England')->lat(), 51.33,
		'a cemetery that is not found falls back to the town');

	%places = ('Kent, England' => $point->(51.2, 0.7));
	is(cemetery_location('Unknown Cemetery, Nowhere, Kent, England'), undef,
		'no marker in the middle of a county if the town is not found');

	%places = ('Highgate Cemetery, London' => $point->(51.56, -0.14));
	is(cemetery_location('Highgate Cemetery, London')->lat(), 51.56, 'a short address is used whole');
};

subtest '_zoom_to_fit' => sub {
	my $zoom = \&Ged2site::Display::cemeteries::_zoom_to_fit;

	is($zoom->([[51.3, 1.4]]), 12, 'one marker has the closest zoom');
	cmp_ok($zoom->([[51.3, 1.4], [51.4, 1.5]]), '>', $zoom->([[51.3, 1.4], [45.5, -73.7]]),
		'markers that are further apart are zoomed out further');
	is($zoom->([[-40, -170], [60, 170]]), 1, 'the whole world is not zoomed out too far');

	# Longitude alone, then latitude alone, must each decide the zoom
	cmp_ok($zoom->([[0, -100], [0, 100]]), '<', 12, 'a spread east to west is fitted');
	cmp_ok($zoom->([[-50, 0], [50, 0]]), '<', 12, 'a spread north to south is fitted');
};

subtest '_cemetery_map' => sub {
	my $map = \&Ged2site::Display::cemeteries::_cemetery_map;

	my $john = { entry => 'I1', title => 'John Smith 1850 - 1920' };
	my $mary = { entry => 'I2', title => 'Mary Smith (n&eacute;e O&apos;Neil) 1852 - 1925' };

	is(scalar(() = $map->([ { cemetery => 'Unknown', people => [ $john ], latitude => '', longitude => '' } ])), 0,
		'no map when no cemetery has a location');

	my ($head, $body) = $map->([
		{ cemetery => "St Peter's Churchyard, Ramsgate", people => [ $john, $mary ], latitude => 51.33, longitude => 1.41 },
		{ cemetery => 'Other Cemetery, Ramsgate', people => [ $john ], latitude => 51.33, longitude => 1.41 },
		{ cemetery => 'Mount Royal, Montreal', people => [ $mary ], latitude => 45.48, longitude => -73.67 },
		{ cemetery => 'Xyzzy', people => [ $john ], latitude => undef, longitude => undef },
	]);

	is(scalar(() = $body =~ /L\.marker\(/g), 2, 'one marker per location');
	like($body, qr/St Peter&#39;s Churchyard.+Other Cemetery/s, 'cemeteries at one location share its popup');
	like($body, qr/entry=I1">John Smith 1850 - 1920/, 'popup links to the person');
	like($body, qr/entry=I2">Mary Smith \(n&eacute;e O&apos;Neil\)/, 'a title is not escaped twice');
	unlike($body, qr/Xyzzy/, 'a cemetery with no location is left out');
	unlike($body, qr/search-box/, 'the search box, which the CSP would block, is left out');

	# Checked here since the browser would otherwise be the first to complain
	my ($csp) = slurp("$root/dynamic-site/lib/VWF/Display.pm") =~ /"Content-Security-Policy:(.+?)\\n"/s;
	$csp =~ s/\\\@/\@/g;
	ok(defined($csp), 'found the Content-Security-Policy');
	my @urls = "$head$body" =~ m{(https://unpkg\.com/[^"'\s]+)}g;
	ok(scalar(@urls), 'HTML::OSM loads files from unpkg.com');
	foreach my $url(@urls) {
		my ($allowed) = $url =~ m{^(https://unpkg\.com/[^/]+/)};
		like($csp, qr/\Q$allowed\E/, "the Content-Security-Policy allows $url");
	}
	like($csp, qr/img-src[^;]+tile\.openstreetmap\.org/, 'the Content-Security-Policy allows the tiles');
};

done_testing();
