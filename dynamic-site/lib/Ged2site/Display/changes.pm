package Ged2site::Display::changes;

# Display changes template file

use warnings;
use strict;
use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'page' => 'changes',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$info->params({ allow => $allowed })};
	return '' if(delete($params{'page'}) ne 'changes');

	my $people = $args{'people'};
	my @change_records = $args{'changes'}->selectall_hash();

	my $changes;

	# Pass a hash ref to the template,
	# key = the date of the change
	# value = an array of hashes of
	#	key = the type the change (e.g. new person, new date added)
	#	value = an array of hashes of the record in changes.psv and the person record in people.csv
	foreach my $record(@change_records) {
		# Retrieve the person entry for this entry in the change table
		#	and make it available to the template
		# FIXME: this can take some time
		my $change_key = $record->{'change'};
		if($change_key =~ /^Added date of birth/) {
			$change_key = 'Added Birth Date';
		} elsif($change_key =~ /^Added date of marriage/) {
			$change_key = 'Added Marriage Date';
		} elsif($change_key =~ /^New person/) {
			$change_key = 'New People';
		}
		push @{$changes->{$record->{'date'}}->{$change_key}}, {
			'record' => $record,
			'person' => $people->fetchrow_hashref(entry => $record->{'xref'})
		};
	}
	return $self->SUPER::html({ changes => $changes, updated => $args{'changes'}->updated() });
}

1;
