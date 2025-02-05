package Ged2site::Data::vwf_log;

# Open /tmp/vwf.log as a database
# Standard CSV file, with no header line

use strict;
use warnings;

use Database::Abstraction;

our @ISA = ('Database::Abstraction');

# Doesn't ignore lines starting with '#' as it's not treated like a CSV file
sub _open {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	return $self->SUPER::_open(sep_char => ',', column_names => ['domain_name', 'time', 'IP', 'country', 'type', 'language', 'http_code', 'template', 'args', 'warnings', 'error'], %args);
}

1;
