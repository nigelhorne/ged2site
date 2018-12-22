package Ged2site::DB::locations;

use XML::Simple;
use Ged2site::DB;

our @ISA = ('Ged2site::DB');

# The database associated with the locations template file

sub new {
	my $proto = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $class = ref($proto) || $proto;

	die "$class: where are the files?" unless($directory || $args{'directory'});
	# init(\%args);

	return bless {
		logger => $args{'logger'} || $logger,
		directory => $args{'directory'} || $directory,	# The directory conainting the tables in XML, SQLite or CSV format
		cache => $args{'cache'} || $cache,
		table => $args{'table'}	# The name of the file containing the table, defaults to the class name
	}, $class;
}

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

sub _open {
	my $self = shift;

	my $xmlfile = File::Spec->catfile($self->{'directory'}, 'locations.xml');
	$self->{'locations'} = XML::Simple::XMLin($xmlfile);

	my @statb = stat($xmlfile);
	$self->{'_updated'} = $statb[9];
}

1;
