package Ged2site::Display::facts;

# Display the facts page

use warnings;
use strict;
use Ged2site::Display;
use File::Spec;
use JSON::MaybeXS;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $allowed = {
		'page' => 'facts',
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	my %params = %{$self->{'_info'}->params({ allow => $allowed })};

	my $json_file = File::Spec->catfile($args{'databasedir'}, 'facts.json');

	my $people = $args{'people'};
	my $p;

	if(open(my $json, '<', $json_file)) {
		my $facts = JSON::MaybeXS->new()->utf8()->decode(<$json>);
		close($json);
		if(my $fb = $facts->{'first_birth'}) {
			$fb->{'person'} = $people->fetchrow_hashref(entry => delete $fb->{'xref'});
		}
		if(my $oa = $facts->{'oldest_age'}) {
			$oa->{'person'} = $people->fetchrow_hashref(entry => delete $oa->{'xref'});
		}
		$p->{'facts'} = $facts;
	} else {
		$p->{'error'} = "Can't open $json_file";
	}
	$p->{'updated'} = $people->updated();
	return $self->SUPER::html($p);
}

1;
