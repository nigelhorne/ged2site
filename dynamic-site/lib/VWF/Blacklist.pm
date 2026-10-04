package VWF::Blacklist;

# Which countries may not use the site.
#
# This list used to be written out three times, in page.fcgi for CGI::ACL, in
# VWF::Allow and in VWF::Display, and the copies had drifted apart (Display
# was missing BY, UA and XH).  All three now ask this module.  Sites can set
# their own list with blacklist_countries in the configuration file.

use strict;
use warnings;

use Carp qw(croak);
use Params::Get;
use Params::Validate::Strict;
use Readonly;

our $VERSION = '0.01';

# Used when the configuration file has no blacklist_countries entry
Readonly my @DEFAULT_COUNTRIES => qw(
	BY MD RU CN BR UY TR MA VE SA CY CO MX IN RS PK UA XH
);

# ISO 3166-1 alpha-2 (plus the user-assigned XA-XZ range), any case
Readonly my $COUNTRY_CODE => qr/\A[A-Za-z]{2}\z/;

=encoding utf8

=head1 NAME

VWF::Blacklist - Country-based access control for VWF pages

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

	use VWF::Blacklist;

	my $bl = VWF::Blacklist->new(countries => $config->{blacklist_countries});
	if($bl->is_blocked($lingua->country())) { ... }

=head1 METHODS

=head2 new

Purpose: build a blacklist.

Args: C<countries> (optional) - an arrayref of two-letter country codes, or a
comma/space separated string, as an XML configuration file gives.  Defaults to the
built-in list.

Returns: a C<VWF::Blacklist>.

Side Effects: none.  Each object has its own list, so two objects never
affect one another.

Usage:

	my $bl = VWF::Blacklist->new(countries => [qw(CN RU)]);

=head3 EXAMPLE

	my $bl = VWF::Blacklist->new();			# built-in list
	my $strict = VWF::Blacklist->new(countries => 'CN, RU');

=head3 API SPECIFICATION

=head4 INPUT

	{
		countries => { type => [ 'arrayref', 'string' ], optional => 1 },
	}

=head4 OUTPUT

	{ type => 'object', isa => 'VWF::Blacklist' }

=head3 MESSAGES

	+--------------------------------+------------------------------+-----------------------+
	| Message                        | Meaning                      | Resolution            |
	+--------------------------------+------------------------------+-----------------------+
	| Invalid country code 'X' in    | An entry is not two letters  | Fix the configuration |
	|   the blacklist                |                              |                       |
	+--------------------------------+------------------------------+-----------------------+

=head3 FORMAL SPECIFICATION

	CC == { c : seq LETTER | #c = 2 }
	Blacklist ≙ [ blocked : ℙ CC | ∀ c : blocked • c = upper(c) ]

	New
	  Blacklist'
	  countries? : seq CC
	  ─────────
	  blocked' = { c : ran countries? • upper(c) }

=cut

sub new
{
	my $class = shift;

	my $args = Params::Validate::Strict::validate_strict({
		schema => { countries => { type => ['arrayref', 'string'], optional => 1 } },
		input => Params::Get::get_params(undef, \@_) || {},
	});

	# Depending on the file format, the configuration file gives either a
	# list or a string such as "CN, RU", so accept both
	my $countries = $args->{countries} // [@DEFAULT_COUNTRIES];
	$countries = [split /[\s,]+/, $countries] unless(ref($countries));

	my %blocked;
	foreach my $code(grep { length } @{$countries}) {
		croak("Invalid country code '$code' in the blacklist") if($code !~ $COUNTRY_CODE);
		$blocked{uc $code} = 1;
	}

	return bless { blocked => \%blocked }, $class;
}

=head2 is_blocked

Purpose: is this country blacklisted?

Args: a two-letter country code, any case.  C<undef> or an empty string
(GeoIP could not place the client) is never blocked, so a lookup failure
does not lock everyone out.

Returns: 1 or 0.

Side Effects: none.

Usage:

	print "Go away\n" if $bl->is_blocked('cn');

=head3 EXAMPLE

	my $bl = VWF::Blacklist->new(countries => ['CN']);
	$bl->is_blocked('cn');	# 1
	$bl->is_blocked('GB');	# 0
	$bl->is_blocked(undef);	# 0

=head3 API SPECIFICATION

=head4 INPUT

	{ country => { type => 'string', optional => 1, position => 0 } }

=head4 OUTPUT

	{ type => 'boolean' }

=head3 MESSAGES

None.

=head3 FORMAL SPECIFICATION

	IsBlocked
	  ΞBlacklist
	  c? : CC ∪ {⊥} ; r! : 𝔹
	  ─────────
	  r! ⇔ (c? ≠ ⊥ ∧ upper(c?) ∈ blocked)

=cut

sub is_blocked
{
	my ($self, $country) = @_;

	return (defined($country) && $self->{blocked}{uc $country}) ? 1 : 0;
}

=head2 countries

Purpose: the blocked countries, for CGI::ACL's C<deny_country>.

Args: none.

Returns: an arrayref of upper-case codes, sorted.

Side Effects: none.

Usage:

	$acl->deny_country(country => $bl->countries());

=head3 EXAMPLE

	VWF::Blacklist->new(countries => 'ru cn')->countries();	# ['CN', 'RU']

=head3 API SPECIFICATION

=head4 INPUT

	{}

=head4 OUTPUT

	{ type => 'arrayref', element_type => 'string' }

=head3 MESSAGES

None.

=head3 FORMAL SPECIFICATION

	Countries
	  ΞBlacklist
	  r! : seq CC
	  ─────────
	  ran r! = blocked ∧ r! is sorted

=cut

sub countries
{
	my $self = shift;

	return [sort keys %{$self->{blocked}}];
}

=head1 LIMITATIONS

Country is only as good as the GeoIP database: VPNs, proxies and stale
databases all defeat it.  It is a noise filter, not a security boundary.

=cut

1;
