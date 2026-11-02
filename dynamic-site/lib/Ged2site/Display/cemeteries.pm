package Ged2site::Display::cemeteries;

# Display the list of cemeteries

use warnings;
use strict;
use HTML::Entities;
use POSIX qw(floor);
use Readonly;
use VWF::Display;

use parent 'VWF::Display';

# The size of the map, which is also what the zoom is chosen to fit into.  The
#	map may be wider than this, since it takes the width of the page
Readonly::Scalar my $MAP_WIDTH => 600;
Readonly::Scalar my $MAP_HEIGHT => 500;
Readonly::Scalar my $TILE_SIZE => 256;
Readonly::Scalar my $PI => 4 * atan2(1, 1);

# A closer view of a lone cemetery doesn't show where it is
Readonly::Scalar my $MAX_ZOOM => 12;
Readonly::Scalar my $MIN_ZOOM => 1;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'cemeteries',
		'lang' => qr/^[A-Za-z]{2}$/,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$self->{'_info'}->params({ allow => $allowed })};

	my $people = $args{'people'};
	my @all_cemeteries = $args{'cemeteries'}->entry();
	my @cemeteries;
	foreach my $cemetery(sort @all_cemeteries) {
		# entry!xref1,xref2!latitude!longitude

		my $xrefs = $args{cemeteries}->xrefs($cemetery);
		my @cemetery_people;
		foreach my $xref(split /,/, $xrefs) {
			# fetchrow_hashref() is undefined when the person isn't in the database
			if(my $person = $people->fetchrow_hashref(entry => $xref)) {
				push @cemetery_people, $person;
			}
		}
		push @cemeteries, {
			cemetery => $cemetery,
			people => \@cemetery_people,
			latitude => $args{'cemeteries'}->latitude($cemetery),
			longitude => $args{'cemeteries'}->longitude($cemetery),
		}
	}

	my ($map_head, $map_body) = _cemetery_map(\@cemeteries);

	return $self->SUPER::html({
		cemeteries => \@cemeteries,
		map_head => $map_head,
		map_body => $map_body,
		updated => $args{'cemeteries'}->updated()
	});
}

# Purpose:      Draw the map of the cemeteries, with a marker for each whose popup
#               lists the people buried or cremated there.  The locations were
#               found by ged2site, so nothing is geocoded while serving a page.
#
# Entry:        $cemeteries - arrayref of hashrefs of cemetery, people, latitude
#               and longitude.
#
# Exit:         The HTML for the page's <head> and the HTML for its <body>, or an
#               empty list if none of the cemeteries has a location.
#
# Side Effects: None.
#
# Notes:        Leaflet only lets the top one of several markers in the same place
#               be clicked, and cemeteries whose address could only be found to
#               the town share a location, so those share a marker.  The search
#               box is left out since the CSP doesn't allow it to reach Nominatim.
sub _cemetery_map
{
	my $cemeteries = shift;

	my %markers;
	foreach my $cemetery(@{$cemeteries}) {
		my ($latitude, $longitude) = @{$cemetery}{qw(latitude longitude)};
		next unless(defined($latitude) && length($latitude) && defined($longitude) && length($longitude));

		my $popup = '<b>' . HTML::Entities::encode_entities($cemetery->{'cemetery'}, q{<>&"'}) . '</b>';
		# The titles are already HTML, ged2site made them with wide_to_html()
		foreach my $person(@{$cemetery->{'people'}}) {
			$popup .= '<br><a href="?page=people&amp;entry=' . $person->{'entry'} . "\">$person->{title}</a>";
		}
		push @{$markers{"$latitude,$longitude"}->{'popups'}}, $popup;
		$markers{"$latitude,$longitude"}->{'point'} = [ $latitude, $longitude ];
	}
	return unless(scalar(keys %markers));

	# Loaded here since the page is still useful, without the map, if HTML::OSM is not installed
	return unless(eval { require HTML::OSM; 1 });

	my @points = map { $_->{'point'} } values %markers;
	my $map = HTML::OSM->new(
		search => 0,
		width => '100%',
		height => "${MAP_HEIGHT}px",
		zoom => _zoom_to_fit(\@points),
	);
	foreach my $marker(values %markers) {
		$map->add_marker($marker->{'point'}, html => join('<hr>', @{$marker->{'popups'}}));
	}
	return $map->onload_render();
}

# Purpose:      Choose the zoom at which all of the markers are on the map.
#               HTML::OSM centres the map on the middle of the markers, but has a
#               fixed zoom, so a family spread over several countries would
#               otherwise start with most of its cemeteries out of view.
#
# Entry:        $points - arrayref of non-empty [ latitude, longitude ] arrayrefs.
#
# Exit:         An integer between $MIN_ZOOM and $MAX_ZOOM.
#
# Side Effects: None.
#
# Notes:        A web map's tiles show the whole world in $TILE_SIZE * 2 ** zoom
#               pixels.  That is linear in longitude but not in latitude, which
#               is why the latitudes go through the Mercator projection.
sub _zoom_to_fit
{
	my $points = shift;

	my @latitudes = sort { $a <=> $b } map { $_->[0] } @{$points};
	my @longitudes = sort { $a <=> $b } map { $_->[1] } @{$points};

	my $mercator = sub { log(sin($_[0] * $PI / 180) + 1) / 2 - log(1 - sin($_[0] * $PI / 180)) / 2 };

	my $zoom = $MAX_ZOOM;
	foreach my $fit(
		[ ($longitudes[-1] - $longitudes[0]) / 360, $MAP_WIDTH ],
		[ ($mercator->($latitudes[-1]) - $mercator->($latitudes[0])) / (2 * $PI), $MAP_HEIGHT ]
	) {
		my ($fraction_of_world, $pixels) = @{$fit};
		next if($fraction_of_world <= 0);	# The markers are in a line, or there's only one

		my $fits = floor(log($pixels / ($TILE_SIZE * $fraction_of_world)) / log(2));
		$zoom = $fits if($fits < $zoom);
	}
	return ($zoom < $MIN_ZOOM) ? $MIN_ZOOM : $zoom;
}

1;
