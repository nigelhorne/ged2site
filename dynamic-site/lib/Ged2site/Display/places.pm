package Ged2site::Display::places;

# Display the places page

use warnings;
use strict;

use Ged2site::Display;

use File::Spec;
use File::Slurp;
use HTML::Entities;
use Locale::Country::Multilingual { use_io_layer => 1 };
use Locale::Language;
use XML::Simple;

use parent 'Ged2site::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
	my $logger = $self->{_logger};

	my $info = $self->{_info};
	my $allow = {
		# 'country' => qr/^[A-Z\s]+$/i,
		'country' => qr/^[\p{L}\s\-\.'’]+$/u,
		'state' => qr/^[A-Z\s]+$/i,
		'town' => qr/^[A-Z\s]+$/i,
		'entry' => qr/^[A-Za-z0-9_\-]+$/,
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

		if($params{'country'} && $params{'state'} && $params{'town'} && $params{'entry'}) {
			# Get a specific person
			my $person = $self->_get_person(\%args, \%params);
			return $self->SUPER::html({ country => $params{'country'}, state => $params{'state'}, town => $params{'town'}, person => $person, %params });
		}
		if($params{'country'} && $params{'state'} && $params{'town'}) {
			# List the people in this town
			my $orig_country = $params{'country'};
			$params{'country'} = $self->_normalize_country_to_english($orig_country);
			my @people = $places->xref({ distinct => 1, %params });
			# FIXME: This could be a lot of database calls - need to combine them
			my %people = map { $_ => $places->name({ xref => $_, distinct => 1 }) } sort grep { defined } @people;
			undef @people;
			$params{'country'} = $orig_country;
			# Add params because the country may have been changed
			return $self->SUPER::html({ country => $orig_country, state => $params{'state'}, town => $params{'town'}, people => \%people, %params });
		}
		if($params{'country'} && $params{'state'}) {
			# List the towns in this counties/states/provinces
			# FIXME: include those where no town is known
			my $orig_country = $params{'country'};
			$params{'country'} = $self->_normalize_country_to_english($orig_country);
			my @towns = $places->town({ distinct => 1, %params });
			@towns = sort grep { defined } @towns;
			$params{'country'} = $orig_country;
			# Add params because the country may have been changed
			return $self->SUPER::html({ country => $params{'country'}, state => $params{'state'}, towns => \@towns, %params });
		}
		if($params{'country'}) {
			# List the counties/states/provinces in this country
			# FIXME: include those where no CSP is known
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
						# Add params because the country has been deleted
						return $self->SUPER::html({ countries => $self->{countries}, %params });
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
					return $self->SUPER::html({ countries => $self->{countries}, %params });
				}
			} else {
				my $orig_country = $params{'country'};
				$params{'country'} = $self->_normalize_country_to_english($orig_country);
				@states = $places->state({ distinct => 1, %params });
				@states = grep { defined } @states;
				$params{'country'} = $orig_country;
			}
			if((scalar(@states) == 0) || !defined($states[0])) {
				# We don't have state information on any of the people
				# in this country
				return $self->SUPER::html({ country => $params{'country'}, people => $places->selectall_hashref(\%params) });
			}
			@states = sort @states;
			# if(($params{'country'} eq 'United States') || ($params{'country'} eq 'Canada')) {
				# @states = map { uc($_) } @states;
			# }
			# Add params because country may have been changed
			return $self->SUPER::html({ country => $params{'country'}, states => \@states, %params });
		}

		# List the countries
		if(!defined($self->{countries})) {
			my @c = sort $places->country(distinct => 1);
			$self->{countries} = \@c;
		}

		if((!defined($self->{_lingua})) || ($self->{_lingua}->requested_language() =~ /^English/)) {
			return $self->SUPER::html({ countries => $self->{countries} });
		}
		$self->{lcm} ||= Locale::Country::Multilingual->new();
		my $code = Locale::Language::language2code($self->{_lingua}->requested_language());
		my @locale_countries = map { encode_entities($self->{lcm}->code2country($self->{lcm}->country2code($_), $code)) } @{$self->{countries}};
		return $self->SUPER::html({ countries => \@locale_countries });
	}

	# Locations database doesn't exist
	return $self->SUPER::html();
}

# Helper: Get a hashref of the data for this person
sub _get_person
{
	my($self, $args, $params) = @_;

	# Read in the .../data/people/$xref.xml file
	my $xml_string;

	eval {
		$xml_string = File::Slurp::read_file(File::Spec->catfile($args->{'database_dir'}, 'people', $params->{'entry'}) . '.xml');
	};
	if($@) {
		if(my $logger = $self->{_logger}) {
			$logger->notice(__PACKAGE__, "$params->{entry}: $@");
		}
		return;
	}

	# Parse the XML string
	if(my $person = XML::Simple->new(ForceArray => 0, KeyAttr => [])->XMLin($xml_string)) {
		return $person->{'person'};
	}
}

# Purpose:      Translate an incoming country name — which may be in any language
#               the visitor's browser requests — into the English name used
#               throughout the places database.  All location records were written
#               by ged2site in English, so every DB query must use English names;
#               this routine is the bridge between what the visitor sends and what
#               the database understands.
#
# Entry:        $self    - a Ged2site::Display::places object; must have {_places}
#                          (a DB handle), {_lingua} (a CGI::Lingua object), and
#                          optionally {lcm} (Locale::Country::Multilingual) already
#                          set up by the html() dispatcher.
#               $country - the country name as the visitor supplied it, possibly in
#                          a non-English language (e.g. "Osterreich" for Austria,
#                          "Allemagne" for Germany).
#
# Exit:         Returns a string: the English country name on success, or the
#               visitor's CGI::Lingua-detected country name as a graceful fallback
#               when the supplied name cannot be mapped to any known ISO country.
#
# Side Effects: Lazily constructs and caches a Locale::Country::Multilingual
#               object in $self->{lcm} on the first call that needs translation;
#               no other persistent state is modified.
#
# Notes:        The fast-path check against the DB avoids unnecessary translation
#               work for the common case where the user is already browsing in
#               English and the name is already in the form the DB expects.
sub _normalize_country_to_english {
	my ($self, $country) = @_;

	# Fast path: if the database already has records filed under this exact name,
	# it is already in the form the DB expects, so no translation is needed.
	# This short-circuits the relatively expensive multilingual lookup for English
	# visitors and for any country name that happens to be the same across languages.
	return $country if $self->{_places}->state({ country => $country });

	# Build the multilingual helper once and reuse it; constructing it is expensive
	# because it loads country-name tables for every supported language.
	$self->{lcm} ||= Locale::Country::Multilingual->new();

	# The browser language tells us how to interpret the country name string --
	# "Allemagne" only parses correctly when we know the input is French.
	my $lang = $self->{_lingua}->language_code_alpha2();

	# Step 1: map the localised name to a language-neutral ISO 3166-1 alpha-2
	# code (e.g. "Osterreich" + lang="de" -> "AT").  If the name is not
	# recognisable at all, fall back to whatever country CGI::Lingua detected
	# from the visitor's IP/Accept-Language header so the page still renders.
	my $code = $self->{lcm}->country2code($country, 'LOCALE_CODE_ALPHA2', $lang)
		or return $self->{_lingua}->country();

	# Step 2: convert the ISO code back to the English name the DB uses
	# (e.g. "AT" -> "Austria").  A second fallback covers the unlikely case
	# where the code exists but has no English mapping in the installed tables.
	return $self->{lcm}->code2country($code, 'en') || $self->{_lingua}->country();
}

1;
