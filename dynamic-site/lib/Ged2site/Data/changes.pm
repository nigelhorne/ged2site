package Ged2site::Data::changes;

# The database associated with the changes template file

use Database::Abstraction;

our @ISA = ('Database::Abstraction');

# There is no entry column in the database
sub new {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	return $self->SUPER::new(no_entry => 1, %args);
}

1;
