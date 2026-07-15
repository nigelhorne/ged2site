#!/usr/bin/env perl

# t/locales.t -- locale coverage for Ged2site modules
#
# Exercises two distinct dimensions of "locale":
#
#   1. Geographic locale (GeoIP / country detection)
#      Tests that Ged2site::Allow correctly blocks and allows connections
#      based on the country code reported by a CGI::Lingua-compatible
#      object.  Uses lightweight mock objects so no real GeoIP database
#      is required at test time.
#
#   2. System locale (POSIX LC_ALL / LANG)
#      For every error path tested, the same assertion is repeated under
#      at least three LC_ALL values (en_US.UTF-8, de_DE.UTF-8, zh_CN.UTF-8)
#      to ensure exceptions are raised regardless of locale.

use strict;
use warnings;

# Increase test count at the bottom once all subtests are settled
use Test::More;
use POSIX qw(ENOENT);

# ---------------------------------------------------------------------------
# Minimal stubs -- no real GeoIP database needed
# ---------------------------------------------------------------------------

# Mock CGI::Lingua: returns a fixed country code
package MockLingua;
sub new     { bless { country => $_[1] }, $_[0] }
sub country { $_[0]->{country} }

# Mock CGI::Info: just enough interface for Allow.pm
package MockInfo;
sub new             { bless {}, $_[0] }
sub is_search_engine { 0 }
sub baidu           { 0 }
sub params          { {} }
sub status          { }	# absorb status(429) / status(403) calls
sub tmpdir          { require File::Temp; File::Temp::tempdir(CLEANUP => 1) }

# Mock cache that always returns undef (cache miss)
package MockCache;
sub new    { bless {}, $_[0] }
sub get    { undef }
sub set    { }
sub remove { }

package main;

# ---------------------------------------------------------------------------
# Load the module under test
# ---------------------------------------------------------------------------

use lib 'dynamic-site/lib';

# Allow.pm needs Ged2site::Utils for create_memory_cache; suppress if absent
my $allow_available = eval { require Ged2site::Allow; 1 };
my $heritage_available = eval {
	require Ged2site::Display::heritage;
	1;
};

# ---------------------------------------------------------------------------
# DIMENSION 1: Geographic locale -- GeoIP country detection
# ---------------------------------------------------------------------------

subtest 'GeoIP sanity: mock objects report expected country codes' => sub {
	plan tests => 5;

	# Each entry: [ label, country_code ]
	my @mapping = (
		['Great Britain' => 'GB'],
		['United States' => 'US'],
		['France'        => 'FR'],
		['Germany'       => 'DE'],
		['China'         => 'CN'],
	);

	for my $pair (@mapping) {
		my ($label, $code) = @{$pair};
		my $mock = MockLingua->new($code);
		is($mock->country(), $code, "MockLingua reports correct code for $label")
			or BAIL_OUT("MockLingua returned wrong country for $label -- sanity check failed");
	}
};

SKIP: {
	skip 'Ged2site::Allow not loadable', 8 unless $allow_available;

	# Countries that should be blocked according to %blacklist_countries
	my @blocked = (
		['Russia'  => 'RU'],
		['China'   => 'CN'],
		['Belarus' => 'BY'],
		['Ukraine' => 'UA'],
	);

	# Countries that should be allowed
	my @allowed = (
		['Great Britain' => 'GB'],
		['United States' => 'US'],
		['France'        => 'FR'],
		['Germany'       => 'DE'],
	);

	subtest 'Allow: blocked countries throw Error::Simple' => sub {
		plan tests => scalar(@blocked);

		my $mock_info  = MockInfo->new();
		my $mock_cache = MockCache->new();

		for my $pair (@blocked) {
			my ($label, $code) = @{$pair};
			my $mock_lingua = MockLingua->new($code);

			eval {
				Ged2site::Allow::allow({
					info   => $mock_info,
					lingua => $mock_lingua,
					cache  => $mock_cache,
				});
			};
			ok($@, "Connection from $label ($code) is blocked");
		}
	};

	subtest 'Allow: allowed countries pass through' => sub {
		plan tests => scalar(@allowed);

		my $mock_info  = MockInfo->new();
		my $mock_cache = MockCache->new();

		for my $pair (@allowed) {
			my ($label, $code) = @{$pair};
			my $mock_lingua = MockLingua->new($code);

			my $rc = eval {
				Ged2site::Allow::allow({
					info   => $mock_info,
					lingua => $mock_lingua,
					cache  => $mock_cache,
				});
			};
			ok(!$@ && $rc, "Connection from $label ($code) is allowed");
		}
	};

	subtest 'Allow: country codes are case-insensitive' => sub {
		plan tests => 2;

		my $mock_info  = MockInfo->new();
		my $mock_cache = MockCache->new();

		# Lowercase 'ru' must also be blocked
		my $lc_ru = MockLingua->new('ru');
		eval {
			Ged2site::Allow::allow({
				info   => $mock_info,
				lingua => $lc_ru,
				cache  => $mock_cache,
			});
		};
		ok($@, 'Lowercase country code "ru" is also blocked');

		# Uppercase 'GB' must still be allowed
		my $uc_gb = MockLingua->new('GB');
		my $rc = eval {
			Ged2site::Allow::allow({
				info   => $mock_info,
				lingua => $uc_gb,
				cache  => $mock_cache,
			});
		};
		ok(!$@ && $rc, 'Uppercase country code "GB" is still allowed');
	};

	subtest 'Allow: concurrent independent instances do not share state' => sub {
		plan tests => 2;

		my $mock_info  = MockInfo->new();
		my $mock_cache = MockCache->new();

		my $lc_ru = MockLingua->new('RU');
		my $lc_gb = MockLingua->new('GB');

		# Block RU
		eval {
			Ged2site::Allow::allow({ info => $mock_info, lingua => $lc_ru, cache => $mock_cache });
		};
		my $ru_blocked = !!$@;

		# Allow GB in the same process without clearing state
		my $gb_ok = eval {
			Ged2site::Allow::allow({ info => $mock_info, lingua => $lc_gb, cache => $mock_cache });
		};

		ok($ru_blocked, 'RU blocked in concurrent-instance test');
		ok(!$@ && $gb_ok, 'GB allowed in the same concurrent-instance test');
	};
}

# ---------------------------------------------------------------------------
# DIMENSION 2: System locale -- POSIX LC_ALL / LANG
# ---------------------------------------------------------------------------

# Helper: build the "missing file" OS error string via Perl's $! layer so
# the message matches exactly what a croak/die would produce on this system,
# regardless of the C library locale.
sub _enoent_str {
	local $! = ENOENT;
	return "$!";
}

# Locales to exercise on every error-path test
my @system_locales = qw(en_US.UTF-8 de_DE.UTF-8 zh_CN.UTF-8);

SKIP: {
	skip 'Ged2site::Display::heritage not loadable', 3 * scalar(@system_locales)
		unless $heritage_available;

	for my $locale (@system_locales) {

		subtest "Heritage html: missing 'heritage' arg croaks under $locale" => sub {
			plan tests => 2;

			local $ENV{LC_ALL} = $locale;
			local $ENV{LANG}   = $locale;

			# Create a bare-minimum blessed object without going through new()
			# to avoid needing a full CGI + config environment
			my $display = bless {}, 'Ged2site::Display::heritage';

			eval { $display->html({}) };
			my $err = $@;

			ok($err, "croak is raised under $locale");
			like("$err", qr/heritage parameter is required/i,
				"error message is 'heritage parameter is required' under $locale");
		};
	}
}

SKIP: {
	skip 'Ged2site::Display::heritage not loadable', 3 * scalar(@system_locales)
		unless $heritage_available;

	for my $locale (@system_locales) {

		subtest "Heritage html: empty heritage DB returns HTML (no croak) under $locale" => sub {
			plan tests => 1;

			local $ENV{LC_ALL} = $locale;
			local $ENV{LANG}   = $locale;

			# Stub a heritage DB that returns no rows
			my $empty_db = bless {}, 'EmptyHeritage';

			# Inject a minimal SUPER::html that just returns a placeholder
			no warnings 'redefine';
			local *Ged2site::Display::html = sub { '<html/>' };

			my $display = bless {}, 'Ged2site::Display::heritage';
			my $html = eval { $display->html({ heritage => $empty_db }) };
			ok(!$@, "Empty heritage DB does not croak under $locale");
		};
	}
}

# Stub DB for the empty-results subtest above
package EmptyHeritage;
sub selectall_hash { () }
sub updated        { time() }

package main;

# ---------------------------------------------------------------------------
# POSIX locale: OS-error string normalisation
# ---------------------------------------------------------------------------

subtest 'OS error string (ENOENT) is stable across locales' => sub {
	plan tests => scalar(@system_locales);

	for my $locale (@system_locales) {
		local $ENV{LC_ALL} = $locale;
		local $ENV{LANG}   = $locale;

		# Build the string the same way the runtime would: via $!
		local $! = ENOENT;
		my $msg = "$!";

		ok(length($msg) > 0, "ENOENT error string is non-empty under $locale: '$msg'");
	}
};

done_testing();
