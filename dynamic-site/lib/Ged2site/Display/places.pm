package Ged2site::Display::places;

# Display the places page

use warnings;
use strict;

use Ged2site::Display;
use Locale::Country::Multilingual { use_io_layer => 1 };

our @ISA = ('Ged2site::Display');

our $lcm;
our $countries;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
	my $logger = $self->{_logger};

	my $info = $self->{_info};
	my $allow = {
		'country' => qr/^[A-Z\s]+$/i,
		'state' => qr/^[A-Z\s]+$/i,
		'entry' => undef,
		'page' => 'places',
		'year' => qr/^\d{3,4}$/,
		'lang' => qr/^[A-Z][A-Z]/i,
		'lint_content' => qr/^\d$/,
	};
	if(my $places = $args{'places'}) {
		my %params = %{$info->params({ allow => $allow })};

		delete $params{'page'};
		delete $params{'lint_content'};
		delete $params{'lang'};

		if((!$params{'country'}) || ($params{'country'} eq 'default')) {
			# List the countries
			if(!defined($countries)) {
				my @c = sort $places->country(distinct => 1);
				$countries = \@c;
			}

			if((!defined($self->{_lingua})) || ($self->{_lingua}->requested_language() =~ /^English/)) {
				return $self->SUPER::html({ countries => $countries });
			}
			$lcm ||= Locale::Country::Multilingual->new();
			my $code = Locale::Language::language2code($self->{_lingua}->requested_language());
			my @locale_countries = map { encode_entities($lcm->code2country($lcm->country2code($_), $code)) } @{$countries};
			return $self->SUPER::html({ countries => \@locale_countries });
		}
		if($params{'country'} && (!$params{'state'}) && !$params{'entry'}) {
			# List the counties/states/provinces in this country
			my @states;
			if($params{'country'} eq 'default') {
				if(my $locale = $self->{_lingua}->locale()) {
					my $country = $locale->name();
					@states = $places->state({ distinct => 1, country => $country });
					if((scalar(@states) == 0) || !defined($states[0])) {
						# No states in this country
						if($logger) {
							$logger->debug(__PACKAGE__, ": no states found in default country $country");
						}
						delete $params{'country'};
						# Add params because country has been deleted
						return $self->SUPER::html({ countries => $countries, %params });
					}
					if($logger) {
						$logger->debug("Setting default country to $country");
					}
					$params{'country'} = $country;
				} else {
					if($logger) {
						$logger->warn(__PACKAGE__, ": can't find country name for ", $params{'country'});
					}
					delete $params{'country'};
					return $self->SUPER::html({ countries => $countries, %params });
				}
			} else {
				my $orig_country = $params{'country'};
				if(!$places->state({ country => $orig_country })) {
					$lcm ||= Locale::Country::Multilingual->new();
					$params{'country'} = $lcm->code2country($lcm->country2code($orig_country , 'LOCALE_CODE_ALPHA2', $self->{_lingua}->language_code_alpha2()), 'en');
					unless(defined($params{'country'})) {
						$params{'country'} = $self->{_lingua}->country();
					}
					if($logger) {
						$logger->debug('Translated country to English, now ', $params{'country'});
					}
				}
				@states = $places->state({ distinct => 1, %params });
				@states = grep { defined } @states;
				$params{'country'} = $orig_country;
			}
			if((scalar(@states) == 0) || !defined($states[0])) {
				# We don't have state information on any of the bands
				# in this country
				return $self->SUPER::html({ country => $params{'country'}, bands => $places->selectall_hashref(\%params) });
			}
			@states = sort @states;
			# if(($params{'country'} eq 'United States') || ($params{'country'} eq 'Canada')) {
				# @states = map { uc($_) } @states;
			# }
			# Add params because country may have been changed
			return $self->SUPER::html({ country => $params{'country'}, states => \@states, %params });
		}

		my @places = $places->places();
		return $self->SUPER::html({
			head => $places->head(year => $params{'year'}),
			places => \@places,
			updated => $places->updated()
		});
	}

	# Locations database doesn't exist
	return $self->SUPER::html();
}

1;
