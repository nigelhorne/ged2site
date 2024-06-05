package Ged2site::DB::locations;

use XML::Simple;
use Database::Abstraction;

our @ISA = ('Database::Abstraction');

# The database associated with the locations template file

sub locations {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if(!defined($self->{'locations'})) {
		$self->_open();
	}
	return $self->{'locations'};
}

sub head {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $year = $args{'year'} || shift;

	if(!defined($self->{'locations'})) {
		$self->_open();
	}
	# print Data::Dumper->new([$self->{'locations'}->{'maps'}->{'map'}])->Dump();
	# exit;
	foreach my $location(@{$self->{'locations'}->{'maps'}->{'map'}}) {
		if($location->{'year'} == $year) {
			return $location->{'head'};
		}
	}
}

# Ensure we open locations.xml not the locations.csv file
sub _open {
	my $self = shift;

	my $xmlfile = File::Spec->catfile($self->{'directory'}, 'locations.xml');
	if(-r $xmlfile) {
		$self->{'locations'} = XML::Simple::XMLin($xmlfile);

		my @statb = stat($xmlfile);
		$self->{'_updated'} = $statb[9];
	} else {
		croak("Can't open $xmlfile");
	}
}

1;
