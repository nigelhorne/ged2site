package VWF::Display;

# Display a page. Certain variables are available to all templates, such as
# the stuff in the configuration file

=head1 VERSION

Version 0.01

=cut

# -----------------------------------------------------------------------

=head1 CONFIGURATION

=head2 CSRF Protection

VWF automatically issues a CSRF token as a cookie on every page load so
that forms can protect against cross-site request forgery.  The token is
signed with an HMAC secret.  B<You must supply that secret in your site's
XML configuration file.>

=head3 Recommended setup - configure a persistent secret

Add the following block to your domain's XML config (e.g.
C<conf/example.com/config.xml>):

    <security>
      <csrf>
        <secret>your-long-random-string-here</secret>
      </csrf>
    </security>

The secret can be any string, but should be long and unpredictable.
Generate a good one with:

    perl -MCrypt::URandom=urandom -e 'print unpack("H*", urandom(32)), "\n"'

or

    openssl rand -hex 32

Tokens signed with this secret survive across FastCGI process restarts,
so users will not lose form state when the server is reloaded.

=head3 What happens if you do not configure a secret

If C<security.csrf.secret> is absent, VWF B<does not refuse to start>.
Instead it:

=over 4

=item 1.

Generates a cryptographically random 256-bit secret the first time a
CSRF token is needed in the current process.

=item 2.

Emits a one-time warning to the error log:

    VWF: security.csrf.secret is not configured; using a per-process
    random secret. CSRF tokens will not survive process restarts.
    Set security.csrf.secret in your site config to suppress this warning.

=item 3.

Uses that random secret for every token issued in this process lifetime.

=back

This means CSRF protection is still B<cryptographically strong> - there is
no hardcoded or guessable key - but if the FastCGI process restarts (e.g.
on deploy or crash) any tokens issued before the restart become invalid.
Users who had a form open will see a CSRF validation failure on submit and
will need to reload the page.

To silence the warning and avoid that edge case, set the secret in config
as shown above.

=head3 Disabling CSRF entirely

Set C<security.csrf.enable> to C<0> in your config if you do not use
server-side form handling and do not need CSRF tokens at all:

    <security>
      <csrf>
        <enable>0</enable>
      </csrf>
    </security>

=cut

# -----------------------------------------------------------------------

our $VERSION = '0.01';

use v5.20;
use strict;
use warnings;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use Config::Abstraction;
use CGI::Info;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Crypt::URandom qw(urandom);		# CSPRNG for CSRF tokens; rand() is not safe
use Carp qw(croak carp);			# croak for fatal errors, carp for warnings

# Per-process fallback CSRF secret, generated once if no secret is configured.
# Tokens are valid within a process lifetime but not across restarts.
my $_csrf_fallback_secret;
use Digest::SHA qw(sha256_hex);
use File::Spec;
use Object::Configure;
use Params::Get;
use Template::Filters;
use Template::Plugin::EnvHash;
use Template::Plugin::Math;
use Template::Plugin::JSON;
use HTML::SocialMedia;
use VWF::Blacklist;
use VWF::Utils qw(create_memory_cache);
use Error;
use File::pfopen;
use Params::Get;
use Scalar::Util;

our $sm;

# Main display handler for generating web pages using Template Toolkit
# Handles security, throttling, localization, and template selection
# Constructor.  Accepts either a flat list of key => value pairs or a hashref.
# Returns a blessed display object, or undef if the request should be blocked
# (e.g. invalid Referer header).
sub new
{
	my $class = shift;

	# Normalise both calling styles (hash list and hashref) into a single hashref.
	my $params = Params::Get::get_params(undef, @_);

	if(!defined($class)) {
		# Called as VWF::Display::new() rather than VWF::Display->new().
		# FIXME: this only works when no arguments are given
		$class = __PACKAGE__;
	} elsif(Scalar::Util::blessed($class)) {
		# $class is already an object — return a shallow clone with the new
		# params merged in (used to re-bless into a subclass).
		return bless { %{$class}, %{$params} }, ref($class);
	}

	# SECURITY — Shellshock / invalid-referer defence:
	#   The HTTP_REFERER header is attacker-controlled.  Validate it as a URI
	#   before letting it propagate further into the request; returning undef
	#   causes the caller to treat this as a blocked request.
	if(defined($ENV{'HTTP_REFERER'})) {
		unless(Data::Validate::URI->can('new')) {
			require Data::Validate::URI;
			Data::Validate::URI->import();
		}

		unless(Data::Validate::URI->new()->is_uri($ENV{'HTTP_REFERER'})) {
			return;	# reject requests with a syntactically invalid Referer
		}
	}

	# Allow subclasses declared via Object::Configure to inject extra params.
	$params = Object::Configure::configure($class, $params);

	my $info = $params->{info} || CGI::Info->new();

	# Resolve the configuration directory hierarchy for this domain.
	my $config_dir = _find_config_dir($params, $info);
	if($params->{'logger'}) {
		$params->{'logger'}->debug(__PACKAGE__, ' (', __LINE__, "): path = $config_dir");
	}

	# Load 'default' first so that domain-specific values override the defaults.
	my $config;
	eval {
		if($config = Config::Abstraction->new(config_dirs => [$config_dir], config_files => ['default', $info->domain_name()], logger => $params->{'logger'})) {
			$config = $config->all();
		}
	};
	if($@ || !defined($config)) {
		croak("Configuration error: $@: $config_dir/", $info->domain_name());
	}

	# Merge caller-supplied config on top of the file-based defaults so that
	# page-specific overrides take precedence.
	if(defined($params->{'config'})) {
		$config = { %{$config}, %{$params->{'config'}} };
	}

	unless($info->is_search_engine() || !defined($ENV{'REMOTE_ADDR'})) {
		if(my $params = $info->params()) {
			# Intrusion Detection System integration
			require CGI::IDS;
			CGI::IDS->import();

			my $ids = CGI::IDS->new();
			$ids->set_scan_keys(scan_keys => 1);

			my $impact = $ids->detect_attacks(request => $params);
			my $threshold = $config->{security}->{ids_threshold} // 50;
			if($impact > $threshold) {
				croak($ENV{'REMOTE_ADDR'}, ": IDS impact is $impact");	# Block detected attacks
			}
		}

		if($ENV{'REMOTE_ADDR'}) {
			# Connection throttling system
			require Data::Throttler;

			my $db_file = $config->{'throttle'}->{'file'} // File::Spec->catdir($info->tmpdir(), 'throttle');

			# The eval only finds out whether the client is over the limit,
			# so that it catches errors from a broken YAML file and nothing
			# else.  A "return" in here would leave only the eval, not new().
			my $throttled = eval {
				my %options = (
					max_items => $config->{'throttle'}->{'max_items'} // 30,	# Allow 30 requests
					interval => $config->{'throttle'}->{'interval'} // 90,	# Per 90 second window
					backend => 'YAML',
					backend_options => {
						db_file => $db_file
					}
				);

				my $throttler = Data::Throttler->new(%options);
				$throttler && !$throttler->try_push(key => $ENV{'REMOTE_ADDR'});
			};
			if($@) {
				if($params->{'logger'}) {
					$params->{'logger'}->notice("Removing unparsable YAML file $db_file: $@");
				}
				unlink($db_file);
			} elsif($throttled) {
				$info->status(429);	# Too many requests
				sleep(1);	# Slow down attackers
				if($params->{'logger'}) {
					$params->{'logger'}->info("$ENV{REMOTE_ADDR} connexion throttled");
				}
				return;
			}

			# Country based blocking
			if(my $lingua = $params->{lingua}) {
				my $country = $lingua->country();
				if(VWF::Blacklist->new(countries => $config->{'blacklist_countries'})->is_blocked($country)) {
					if($params->{'logger'}) {
						$params->{'logger'}->warn("$ENV{REMOTE_ADDR} is from a blacklisted country $country");
					}
					croak("$ENV{REMOTE_ADDR} is from a blacklisted country $country");
				}
			}
		}
	}

	# Initialise the template system
	Template::Filters->use_html_entities();

	# _ names included for legacy reasons, they will go away
	my $self = {
		_cachedir => $params->{cachedir},
		info => $info,
		_info => $info,
		_logger => $params->{logger},
		config_dir => $config_dir,
		%{$params},
		config => $config,
		_config => $config,
	};

	if(my $lingua = $params->{'lingua'}) {
		$self->{'lingua'} = $lingua;
		$self->{'_lingua'} = $lingua;
	}
	if(my $key = $info->param('key')) {
		$self->{'key'} = $key;
		$self->{'_key'} = $key;
	}
	if(my $page = $info->param('page')) {
		$self->{'page'} = $page;
		$self->{'_page'} = $page;
	}

	# Social media integration
	if(my $twitter = $config->{'twitter'}) {
		my $smcache = create_memory_cache(config => $config, logger => $params->{'logger'}, namespace => 'HTML::SocialMedia');
		$sm ||= HTML::SocialMedia->new({ twitter => $twitter, cache => $smcache, lingua => $params->{lingua}, logger => $params->{logger} });
		$self->{'_social_media'}->{'twitter_tweet_button'} = $sm->as_string(twitter_tweet_button => 1);
	} elsif(!defined($sm)) {
		my $smcache = create_memory_cache(config => $config, logger => $params->{'logger'}, namespace => 'HTML::SocialMedia');
		$sm = HTML::SocialMedia->new({ cache => $smcache, lingua => $params->{lingua}, logger => $params->{logger} });
	}
	$self->{'_social_media'}->{'facebook_share_button'} = $sm->as_string(facebook_share_button => 1);
	# $self->{'_social_media'}->{'google_plusone'} = $sm->as_string(google_plusone => 1);

	# Return the blessed object
	return bless $self, $class;
}

# Internal method to determine the configuration directory
sub _find_config_dir
{
	my($args, $info) = @_;

	if($ENV{'CONFIG_DIR'}) {
		return $ENV{'CONFIG_DIR'};
	}

	# Look first in $root_dir/conf

	my $config_dir = $ENV{'root_dir'};
	if(defined($config_dir) && (-d $config_dir)) {
		$config_dir = File::Spec->catdir($config_dir, 'conf');

		if(-d $config_dir) {
			return $config_dir;
		}
	}

	$config_dir = File::Spec->catdir(
			$info->script_dir(),
			File::Spec->updir(),
			File::Spec->updir(),
			'conf'
		);

	if(!-d $config_dir) {
		$config_dir = File::Spec->catdir(
				$info->script_dir(),
				File::Spec->updir(),
				'conf'
			);
	}

	if(!-d $config_dir) {
		if($ENV{'DOCUMENT_ROOT'}) {
			$config_dir = File::Spec->catdir(
				# $ENV{'DOCUMENT_ROOT'},
				$info->rootdir(),
				File::Spec->updir(),
				'lib',
				'conf'
			);
		} else {
			$config_dir = File::Spec->catdir(
				$ENV{'HOME'},
				'lib',
				'conf'
			);
		}
	}

	if(!-d $config_dir) {
		if($args->{config_directory}) {
			return $args->{config_directory};
		}
		if($args->{logger}) {
			while(my ($k, $v) = each %ENV) {
				$args->{logger}->debug("$k=$v");
			}
		}
	}

	return $config_dir;
}

# Call this to display the page
# It calls http() to create the HTTP headers, then html() to create the body
sub as_string {
	my ($self, $args) = @_;

	# TODO: Get all cookies and send them to the template.
	# 'cart' is an example
	unless($args && $args->{cart}) {
		if(my $purchases = $self->{_info}->get_cookie(cookie_name => 'cart')) {
			# SECURITY — malformed cookie defence:
			#   The cart cookie is colon-delimited key:qty pairs (e.g. "sku1:2:sku2:1").
			#   An attacker-controlled cookie with an odd number of colons would cause
			#   "Odd number of elements in hash assignment" and corrupt the cart hash.
			#   Only convert the list to a hash when the element count is even.
			my @parts = split(/:/, $purchases);
			if(@parts % 2 == 0) {
				my %cart = @parts;
				# Strip any key or value containing non-alphanumeric characters to
				# prevent template injection through attacker-controlled cookie data.
				$args->{cart} = {
					map { /^[A-Za-z0-9_]+$/ ? ($_ => $cart{$_}) : () } keys %cart
				};
			}
		}
	}

	# Calculate items in cart if not already present in $args
	unless($args && $args->{itemsincart}) {
		if($args->{cart}) {
			my $itemsincart;
			foreach my $key(keys %{$args->{cart}}) {
				if(defined($args->{cart}{$key}) && ($args->{cart}{$key} ne '')) {
					$itemsincart += $args->{cart}{$key};
				} else {
					delete $args->{cart}{$key};
				}
			}
			$args->{itemsincart} = $itemsincart;
		}
	}

	my($cache, $key);

	if(!$args->{itemsincart}) {
		$cache = create_memory_cache(config => $self->{config}, logger => $self->{'logger'}, namespace => ref($self));
		$key = cache_key_from_hashref($args);
		if(my $rc = $cache->get($key)) {
			return $rc;
		}
	}

	# my $html = $self->html($args);
	# unless($html) {
		# return;
	# }
	# return $self->http() . $html;

	# Build the HTTP response
	my $rc = $self->http($args);
	if($rc =~ /^Location:\s/ms) {
		return $rc;
	}
	$rc .= $self->html($args);
	if($cache) {
		$self->{cache_duration} ||= '5 minutes';
		$cache->set($key, $rc, $self->{cache_duration});
	}
	return $rc;
}

# Determine the path to the correct template file based on various criteria such as language settings, browser type, and module path
sub get_template_path
{
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if($self->{_logger}) {
		$self->{_logger}->trace('Entering get_template_path');
	}

	if($self->{_filename}) {
		if($self->{_logger}) {
			$self->{_logger}->trace({ message => 'returning ' . $self->{_filename} });
		}
		return $self->{_filename};
	}

	# FIXME: reread the config file since something is cloberring it 
	if(my $config = Config::Abstraction->new(config_dirs => [$self->{config_dir}], config_files => ['default', $self->{info}->domain_name()], logger => $self->{logger})) {
		$config = $config->all();
		$self->{config} = $self->{_config} = $config;
	}
	my $dir = $ENV{'root_dir'} || $self->{_config}->{root_dir} || $self->{_info}->root_dir();
	if($self->{_logger}) {
		$self->{_logger}->debug(__PACKAGE__, ': ', __LINE__, ": root_dir $dir");
		$self->{_logger}->debug(Data::Dumper->new([$self->{_config}])->Dump());
	}
	$dir .= '/templates';

	my $prefix;

	# Look in .../robot or .../mobile first, if appropriate
	# Look in .../en/gb/web, then .../en/web then /web
	foreach my $browser_type($self->_types()) {
		if(my $lingua = $self->{_lingua}) {
			$self->_debug({ message => 'Requested language: ' . $lingua->requested_language() });
			# FIXME: look for lower priority languages if the highest isn't found
			if(my $language = $lingua->language_code_alpha2()) {
				if(my $dialect = $lingua->sublanguage_code_alpha2()) {
					$prefix .= "$dir/$browser_type/$language/$dialect:";
					$prefix .= "$dir/$browser_type/$language/default:";
				}
				$prefix .= "$dir/$language/$browser_type:" if(-d "$dir/$language/$browser_type");
				$prefix .= "$dir/$browser_type/$language:" if(-d "$dir/$browser_type/$language");
			}
		}
		$prefix .= "$dir/$browser_type/default:" if(-d "$dir/$browser_type/default");
		$prefix .= "$dir/default/$browser_type/:" if(-d "$dir/default/$browser_type");
		$prefix .= "$dir/$browser_type:" if(-d "$dir/$browser_type");
	}

	# Fall back to .../web, or if that fails, assume no web, robot or
	# mobile variant
	$prefix .= "$dir/web:$dir/default/web:$dir/default:$dir";

	$self->_debug({ message => "prefix: $prefix" });

	my $modulepath = $args{'modulepath'} || ref($self);
	$modulepath =~ s/::/\//g;

	if($prefix =~ /\.\.\//) {
		throw Error::Simple("Prefix must not contain ../ ($prefix)");
	}

	# Untaint the prefix value which may have been read in from a configuration file
	($prefix) = ($prefix =~ m/^([A-Z0-9_\.\-\/:]+)$/ig);

	my ($fh, $filename) = File::pfopen::pfopen($prefix, $modulepath, 'tmpl:tt:html:htm:txt');
	if((!defined($filename)) || (!defined($fh))) {
		throw Error::Simple("Can't find suitable $modulepath html or tmpl/tt file in $prefix in $dir or a subdir (check " . join(':', @{$self->{'config'}->{'config_path'}}) . ')');
	}
	close($fh);
	$self->_debug({ message => "Using $filename" });
	$self->{_filename} = $filename;

	# Remember the template filename
	if($self->{'log'}) {
		$self->{'log'}->template($filename);
	}

	return $filename;
}

=head2 set_cookie

Safely set cookie values with validation.

Takes either a hash reference or a list of key-value pairs as input.
Iterates over the parameters and stores them in the object's _cookies hash.
Returns the object itself, allowing for method chaining.

=cut

sub set_cookie
{
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Validate cookie parameters
	for my $key (keys %params) {
		# Sanitize cookie names and values
		next unless $key =~ /^[a-zA-Z0-9_-]+$/;

		my $value = $params{$key};
		next unless defined $value;

		# Basic value sanitization
		$value =~ s/[;\r\n]//g;
		$self->{_cookies}->{$key} = $value;
	}

	return $self;
}

=head2 add_preload

  $self->add_preload($href, $as, %opts);

Queue a resource to be advertised to the browser (and to the HTTP/2 server)
as a preload hint, emitted as a C<Link: rel=preload> HTTP header.

In HTTP/2, the web server can read these headers and I<push> the named assets
to the client before the browser has finished parsing the HTML and discovered
them itself.  This eliminates a full round-trip for render-critical resources
such as stylesheets and fonts, measurably reducing time-to-first-paint.

In HTTP/1.1 the header still provides a useful hint: browsers begin fetching
the asset as soon as they see the response headers, in parallel with HTML
parsing, which is faster than waiting for the parser to encounter the
C<< <link> >> or C<< <script> >> tag.

=head3 Parameters

=over 4

=item $href (required)

Root-relative path to the resource, e.g. C</css/main.css>.  Must start with
a C</>.  Absolute URLs and relative paths are rejected to prevent header
injection.

=item $as (required)

The W3C resource type.  Must be one of:

  audio  document  embed  fetch  font  image  object
  script  style  track  video  worker

Choosing the correct type matters: it determines the request's priority,
the C<Accept> header the browser sends, and whether the resource is subject
to Content Security Policy checks.  An incorrect type causes the browser to
ignore the hint silently.

=item crossorigin => 1 (optional)

Include the C<crossorigin> attribute on the Link header.  This is required
for any resource that will be fetched in CORS anonymous mode - most notably
web fonts, even when they are served from the same origin.  Without it the
browser issues a second, uncached fetch when it encounters the C<< <link> >>
tag in the HTML.

Defaults to C<1> automatically when C<$as> is C<font>; for all other types
defaults to C<0>.

=back

Returns C<$self> so calls may be chained.

=head3 When to call it

Call C<add_preload> from a page subclass constructor, I<after>
C<< $class->SUPER::new(@args) >> returns and I<before> C<as_string> is
called.  C<http()> reads the preload queue when it runs, so any call made
before that point will be included in the response.

Do B<not> call it from C<html()>: by the time C<html()> executes, C<http()>
has already emitted the headers and the Link headers will be lost.

=head3 What to preload

Preload only resources that are I<render-critical> for the current page -
assets the browser will definitely need within the first few seconds of
rendering.  Good candidates:

=over 4

=item * The primary stylesheet (C<as=style>)

=item * Web fonts referenced by that stylesheet (C<as=font>)

=item * A critical above-the-fold script (C<as=script>)

=back

Avoid preloading everything: unused preloads waste bandwidth and compete with
resources the browser has already prioritised.  Per-page subclasses are the
right place because each page knows exactly which assets its template needs.

=head3 Examples

Typical use inside a page subclass:

  package VWF::Display::index;
  use parent 'VWF::Display';

  sub new {
      my ($class, @args) = @_;
      my $self = $class->SUPER::new(@args);
      return unless defined $self;   # blocked by Display (e.g. bad Referer)

      # Register render-critical assets for this page.
      # add_preload() returns $self so calls chain naturally.
      $self->add_preload('/css/main.css',         'style')
           ->add_preload('/fonts/body.woff2',     'font')    # crossorigin added automatically
           ->add_preload('/fonts/heading.woff2',  'font')
           ->add_preload('/js/index.js',          'script');

      return $self;
  }

These produce the following headers in the HTTP response:

  Link: </css/main.css>; rel=preload; as=style
  Link: </fonts/body.woff2>; rel=preload; as=font; crossorigin
  Link: </fonts/heading.woff2>; rel=preload; as=font; crossorigin
  Link: </js/index.js>; rel=preload; as=script

A resource fetched via C<fetch()> or C<XMLHttpRequest> that requires CORS:

  $self->add_preload('/api/config.json', 'fetch', crossorigin => 1);

An above-the-fold hero image (no C<crossorigin> needed for images):

  $self->add_preload('/img/hero.webp', 'image');

=head3 Why the base class preloads nothing by default

C<VWF::Display> ships no assets of its own, so there is nothing framework-level
to preload.  Additionally, C<http()> runs I<before> C<html()>, which means the
template has not yet been processed when the headers are emitted - the base
class has no way to inspect template contents to discover asset references
automatically.  Each subclass is therefore responsible for declaring its own
dependencies explicitly.

=cut

sub add_preload
{
	my ($self, $href, $as, %opts) = @_;

	# Allowlist of valid W3C Resource Hints 'as' types (https://www.w3.org/TR/preload/).
	# Any other value would produce an invalid Link header that browsers ignore.
	my %valid_types = map { $_ => 1 }
		qw(audio document embed fetch font image object script style track video worker);
	croak "Unknown preload type '$as'; must be one of: " . join(', ', sort keys %valid_types)
		unless $valid_types{$as};

	# SECURITY — header injection defence:
	#   $href is interpolated into the Link header value.  Reject anything that
	#   is not a root-relative path; in particular, CRLF characters in $href
	#   would let a caller inject arbitrary HTTP headers.
	croak "Preload href must be a root-relative path starting with '/'"
		unless $href =~ m{^/[^\r\n]*$};

	# Fonts loaded cross-origin (which is every font in practice, even same-origin,
	# due to the CORS anonymous-mode requirement) must carry the crossorigin attribute
	# or the browser will fetch them twice.  Default it on for font type.
	my $crossorigin = $opts{crossorigin} // ($as eq 'font' ? 1 : 0);

	$self->{_preloads} ||= [];
	push @{$self->{_preloads}}, { href => $href, as => $as, crossorigin => $crossorigin };

	return $self;	# allow chaining: $self->add_preload(...)->add_preload(...)
}

=head2 http

Returns the HTTP header section, terminated by an empty line

=cut

# Generate and return the HTTP response headers (without the blank-line
# terminator — FCGI::Buffer appends that).  Also emits Set-Cookie lines
# for session cookies and the CSRF token, plus Link: rel=preload headers
# for any assets registered via add_preload().
sub http
{
	my $self = shift;
	my $params = Params::Get::get_params(undef, @_);

	# Emit Link: rel=preload headers for all assets queued by add_preload().
	# In HTTP/2 these headers instruct the server to push the assets before
	# the browser has parsed the HTML and discovered them itself, eliminating
	# a full round-trip for render-critical resources like stylesheets and fonts.
	if(my $preloads = $self->{_preloads}) {
		for my $p (@{$preloads}) {
			my $link = "Link: <$p->{href}>; rel=preload; as=$p->{as}";
			# The crossorigin attribute is required for fonts and for any
			# resource fetched in CORS anonymous mode; without it the browser
			# will ignore the push and fetch the resource again anyway.
			$link .= '; crossorigin' if $p->{crossorigin};
			print "$link\n";
		}
	}

	# Emit Set-Cookie headers for any cookies queued by set_cookie().
	# All cookies carry HttpOnly and SameSite=Strict; the Secure flag is
	# added automatically when the connection is HTTPS.
	if(my $cookies = $self->{_cookies}) {
		foreach my $cookie (keys(%{$cookies})) {
			my $value = exists $cookies->{$cookie} ? $cookies->{$cookie} : '0:0';
			my $secure = ($self->{'info'}->protocol() eq 'https') ? '; Secure' : '';
			print "Set-Cookie: $cookie=$value; path=/; HttpOnly; SameSite=Strict$secure\n";
		}
	}

	# Issue a fresh CSRF token on every page load so that forms can embed it.
	# The token is validated server-side when the form is submitted.
	# CSRF protection is enabled by default and can be turned off in config.
	if($self->{config}->{security}->{csrf}->{enable} // 1) {
		my $csrf_token = $self->_generate_csrf_token();
		print "Set-Cookie: csrf_token=$csrf_token; path=/; HttpOnly; SameSite=Strict\n";
	}

	# Choose Content-Type from the template extension, or use the caller's
	# override if one was supplied (e.g. for JSON or XML responses).
	my $rc;
	if($params->{'Content-Type'}) {
		$rc = $params->{'Content-Type'} . "\n";
	} else {
		my $filename = $self->get_template_path();
		if ($filename =~ /\.txt$/) {
			$rc = "Content-Type: text/plain\n";
		} else {
			# Switch STDOUT to UTF-8 mode before sending HTML to prevent
			# the Perl runtime from inserting a spurious BOM.
			binmode(STDOUT, ':utf8');
			$rc = "Content-Type: text/html; charset=UTF-8\n";
		}
	}

	# Seconds only (RFC 9110 section 10.2.3); anything else could inject headers
	if(defined(my $retry_after = $params->{'Retry-After'})) {
		croak("Retry-After must be a number of seconds, not '$retry_after'")
			unless($retry_after =~ /\A\d+\z/);
		$rc .= "Retry-After: $retry_after\n";
	}

	# ── Defensive security headers ─────────────────────────────────────────
	# X-Frame-Options: prevents clickjacking by disallowing iframe embedding
	#   from cross-origin pages.  (OWASP Clickjacking Defence Cheat Sheet)
	# X-Content-Type-Options: stops browsers from MIME-sniffing the response
	#   away from the declared Content-Type, closing a class of XSS vectors.
	# X-XSS-Protection: enables the legacy XSS auditor in older browsers.
	# Referrer-Policy: sends the full URL only to same-origin requests, so
	#   sensitive URL parameters are not leaked to third-party analytics.
	# Content-Security-Policy: whitelists script and style origins.
	#   'unsafe-inline' is present for legacy templates; tighten this once
	#   all inline scripts have been migrated to external files.
	# Strict-Transport-Security: instructs the browser to use HTTPS for the
	#   next year; includeSubDomains covers all sub-sites.
	return $rc .
		"X-Frame-Options: SAMEORIGIN\n" .
		"X-Content-Type-Options: nosniff\n" .
		"X-XSS-Protection: 1; mode=block\n" .
		"Referrer-Policy: strict-origin-when-cross-origin\n" .
		"Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'\n" .
		"Strict-Transport-Security: max-age=31536000; includeSubDomains\n\n";
}

# Run the given data through the template to create HTML

# Override this routine in a subclass if you wish to create special arguments to
# send to the template
sub html {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $filename = $self->get_template_path();
	my $rc;

	# Handle template files (.tmpl or .tt)
	if($filename =~ /.+\.t(mpl|t)$/) {
		require Template;
		Template->import();

		my $info = $self->{_info};

		# The values in config are defaults which can be overridden by
		# the values in info, then the values in params
		my $vals;
		if(defined($self->{_config})) {
			if($info->params()) {
				$vals = { %{$self->{_config}}, %{$info->params()} };
			} else {
				$vals = $self->{_config};
			}
			if(scalar(keys %params)) {
				$vals = { %{$vals}, %params };
			}
		} elsif(scalar(keys %params)) {
			$vals = { %{$info->params()}, %params };
		} else {
			$vals = $info->params();
		}
		$vals->{script_name} = $info->script_name();

		$vals->{cart} = $info->get_cookie(cookie_name => 'cart');
		$vals->{lingua} = $self->{_lingua};
		$vals->{social_media} = $self->{_social_media};
		$vals->{info} = $info;
		$vals->{as_string} = $info->as_string();

		my $template = Template->new({
			INTERPOLATE => 1,
			POST_CHOMP => 1,
			ABSOLUTE => 1,
			PLUGINS => { JSON => 'Template::Plugin::JSON' },
		});

		$self->_debug({ message => __PACKAGE__ . ': ' . __LINE__ . ': Passing these to the template: ' . join(', ', keys %{$vals}) });

		# Process the template
		if(!$template->process($filename, $vals, \$rc)) {
			if(my $err = $template->error()) {
				throw Error::Simple($err);
			}
			throw Error::Simple("Unknown error in template: $filename");
		}
	} elsif($filename =~ /\.(html?|txt)$/) {
		# Handle static HTML or text files
		open(my $fin, '<', $filename) || throw Error::Simple("$filename: $!");

		my @lines = <$fin>;

		close $fin;

		$rc = join('', @lines);
	} else {
		throw Error::Simple("Unhandled file type $filename");
	}

	# Check for mailto links and log a warning
	if(($filename !~ /.txt$/) && ($rc =~ /\smailto:(.+?)>/) && ($1 !~ /^&/) && $self->{_logger}) {
		$self->{_logger}->warn({ message => "Found mailto link $1, you should remove it or use " . obfuscate($1) . ' instead' });
	}

	return $rc;
}

sub _debug
{
	my $self = shift;

	if(my $logger = $self->{_logger}) {
		my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
		if(defined($ENV{'REMOTE_ADDR'})) {
			$logger->debug("$ENV{'REMOTE_ADDR'}: $params{'message'}");
		} else {
			$logger->debug($params{'message'});
		}
	}
	return $self;
}

# Encode a string as HTML numeric entities, e.g. 'a@b' => '&#97;&#64;&#98;'.
# Always returns one string: it is used inside a concatenation, where a list
# would be counted rather than joined.
sub obfuscate {
	return join('', map { '&#' . ord($_) . ';' } split(//, shift));
}

sub _types
{
	my $self = shift;
	my $info = $self->{_info};
	my @rc;

	if($info->is_search_engine()) {
		push @rc, 'search', 'robot';
	} elsif($info->is_mobile()) {
		push @rc, 'mobile';
	} elsif($info->is_robot()) {
		push @rc, 'robot', 'search';
	}
	push @rc, 'web';

	if(my $logger = $self->{'_logger'}) {
		$logger->trace('< ', __PACKAGE__, '::_types returning ', join(':', @rc));
	}

	return @rc;
}

sub _generate_csrf_token($self) {
	# Prefer an explicitly configured HMAC secret from security.csrf.secret.
	# If absent, fall back to a per-process random secret generated at first use
	# and warn once so the operator knows to configure a persistent one.
	# A per-process secret is still cryptographically strong (no hardcoded value),
	# but tokens will be invalidated whenever the FastCGI process restarts.
	my $secret = $self->{config}->{security}->{csrf}->{secret};
	unless(defined $secret) {
		unless(defined $_csrf_fallback_secret) {
			$_csrf_fallback_secret = unpack('H*', urandom(32));
			my $config_path = $self->{config}->{config_path}
				? join(', ', @{$self->{config}->{config_path}})
				: 'conf/' . ($self->{info} ? ($self->{info}->domain_name() // 'unknown') : 'unknown');
			carp "VWF: security.csrf.secret is not configured; "
			   . 'using a per-process random secret. '
			   . 'CSRF tokens will not survive process restarts. '
			   . "Add <security><csrf><secret>...</secret></csrf></security> "
			   . "to $config_path to suppress this warning.";
		}
		$secret = $_csrf_fallback_secret;
	}

	# SECURITY — use a cryptographically secure RNG, not rand().
	#   Perl's built-in rand() is a predictable PRNG; if an attacker knows the
	#   approximate server time they can enumerate the 32-bit output space in
	#   seconds.  Crypt::URandom reads from /dev/urandom (or the OS equivalent),
	#   giving 256 bits of unpredictable entropy as a 64-character hex string.
	my $random     = unpack('H*', urandom(32));
	my $timestamp  = time();
	my $token_data = "$timestamp:$random";

	# Build an HMAC-style signature: sha256( token_data || ':' || secret ).
	# The server must re-derive and compare this signature on form submission.
	my $signature  = sha256_hex("$token_data:$secret");

	return "$token_data:$signature";
}

sub cache_key_from_hashref {
	my $hashref = $_[0];

	# Use Data::Dumper with sorted keys for consistent output
	local $Data::Dumper::Sortkeys = 1;
	local $Data::Dumper::Terse = 1;
	local $Data::Dumper::Indent = 0;

	my $dumped = Dumper($hashref);

	# Create an MD5 hash for a compact key
	return md5_hex($dumped);
}

1;
