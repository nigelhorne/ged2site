package Ged2site::Display::facts;

# Display the facts page

use warnings;
use strict;
use Ged2site::Display;
use File::Spec;
use JSON::MaybeXS;

our @ISA = ('Ged2site::Display');

sub html
{
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $json_file = File::Spec->catfile($args{'database_dir'}, 'facts.json');

	my $people = $args{'people'};
	my $p;

	if(open(my $json, '<', $json_file)) {
		my $facts;
		eval {
			local $/;	# Ensure all lines are slurped
			$facts = JSON::MaybeXS->new()->decode(<$json>);
		};
		if ($@) {
			$p->{'error'} = "Failed to parse $json_file: $@";
			return $self->SUPER::html($p);
		}
		close($json);

		for my $key (qw(first_birth oldest_age most_children youngest_marriage oldest_marriage)) {
			if(my $f = $facts->{$key}) {
				$f->{'person'} = $people->fetchrow_hashref(entry => delete $f->{'xref'});
			}
		}
		
		if(my $bs = $facts->{'both_sides'}) {
			foreach my $xref(@{$bs->{'xrefs'}}) {
				push @{$bs->{'people'}}, $people->fetchrow_hashref(entry => $xref);
			}
			delete $bs->{'xrefs'};
		}
		if(my $over_100s = $facts->{'people_over_100'}) {
			foreach my $xref(@{$over_100s->{'xrefs'}}) {
				push @{$over_100s->{'people'}}, $people->fetchrow_hashref(entry => $xref);
			}
			delete $over_100s->{'xrefs'};
		}
		if(my $lm = $facts->{'longest_marriage'}) {
			$lm->{'person'} = $people->fetchrow_hashref(entry => delete $lm->{'xref'});
			$lm->{'spouse'} = $people->fetchrow_hashref(entry => delete $lm->{'spouse_xref'});
		}
		$p->{'facts'} = $facts;
	} else {
		$p->{'error'} = "Can't open $json_file";
	}
	$p->{'updated'} = $people->updated();
	return $self->SUPER::html($p);
}

1;
