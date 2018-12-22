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

sub location {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $year = $args{'year'};

	if(!defined($self->{'locations'})) {
		$self->_open();
	}
	return $self->{'locations'}->{$year};
}

sub _open {
	my $self = shift;

	$self->{'locations'} = XML::Simple::XMLin($self->{'directory'} . '/locations.xml');

	# TODO - set $self->{'_updated'};
}

1;
