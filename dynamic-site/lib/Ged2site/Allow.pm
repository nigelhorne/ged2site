use Ged2site::Utils;

# See https://github.com/nigelhorne/CGI-Allow

package Ged2site::Allow;

# Ged2site is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

use strict;
use warnings;
use File::Spec;
use Carp;
use Error;

our %blacklist_countries = (
	'BY' => 1,
	'MD' => 1,
	'RU' => 1,
	'CN' => 1,
	'BR' => 1,
	'UY' => 1,
	'TR' => 1,
	'MA' => 1,
	'VE' => 1,
	'SA' => 1,
	'CY' => 1,
	'CO' => 1,
	'MX' => 1,
	'IN' => 1,
	'RS' => 1,
	'PK' => 1,
	'UA' => 1,
);

our %blacklist_agents = (
	'masscan' => 'Masscan',
	'WBSearchBot' => 'Warebay',
	'MJ12' => 'Majestic',
	'Mozilla/4.0 (compatible; Vagabondo/4.0; webcrawler at wise-guys dot nl; http://webagent.wise-guys.nl/; http://www.wise-guys.nl/)' => 'wise-guys',
	'zgrab' => 'Mozilla/5.0 zgrab/0.x',
	'iodc' => 'Mozilla/5.0 (compatible; IODC-Odysseus Survey 21796-100-051215155936-107; +https://iodc.co.uk)',
);

our %status;

sub allow {
	if(!defined($ENV{'REMOTE_ADDR'})) {
		# Not running as a CGI
		return 1;
	}

	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $logger = $args{'logger'};
	my $addr = $ENV{'REMOTE_ADDR'};

	if(defined($status{$addr})) {
		# Cache the value
		if($logger) {
			$logger->info("$addr: cached value " . $status{$addr});
		}
		return $status{$addr};
	}
	if($logger) {
		$logger->trace('In ', __PACKAGE__);
	}

	if($ENV{'HTTP_USER_AGENT'}) {
		my $blocked = $blacklist_agents{$ENV{'HTTP_USER_AGENT'}};
		if($blocked) {
			if($logger) {
				$logger->info("$blocked blacklisted");
			}
			$status{$addr} = 0;
			throw Error::Simple("$addr: $blocked is blacklisted", 1);
		}
	}

	my $info = $args{'info'};
	if(!defined($info)) {
		if($logger) {
			$logger->warn('Info not given');
		} else {
			carp('Info not given');
		}
		$status{$addr} = 1;
		return 1;
	}

	unless($info->is_search_engine()) {
		require Data::Throttler;
		Data::Throttler->import();

		# Handle YAML Errors
		my $db_file = File::Spec->catfile($info->tmpdir(), 'throttle');
		eval {
			my $throttler = Data::Throttler->new(
				max_items => 15,
				interval => 90,
				backend => 'YAML',
				backend_options => {
					db_file => $db_file
				}
			);

			unless($throttler->try_push(key => $ENV{'REMOTE_ADDR'})) {
				if($logger) {
					# Recommend you send HTTP 429 at this point
					$logger->warn("$ENV{REMOTE_ADDR} throttled");
				}
				$status{$addr} = 0;
				throw Error::Simple("$addr has been throttled");
			}
		};
		if($@) {
			if($logger) {
				$logger->debug("removing $db_file");
			}
			unlink($db_file);
		}

		unless($ENV{'REMOTE_ADDR'} =~ /^192\.168\./) {
			my $lingua = $args{'lingua'};
			if(defined($lingua) && $blacklist_countries{uc($lingua->country())}) {
				if($logger) {
					$logger->warn("$ENV{REMOTE_ADDR} blocked connexion from ", $lingua->country());
				}
				$status{$addr} = 0;
				throw Error::Simple("$ENV{REMOTE_ADDR}: blocked connexion from " . $lingua->country(), 0);
			}
		}

		if(defined($ENV{'REQUEST_METHOD'}) && ($ENV{'REQUEST_METHOD'} eq 'GET')) {
			my $params = $info->params();
			if(defined($params) && keys(%{$params})) {
				require CGI::IDS;
				CGI::IDS->import();

				my $ids = CGI::IDS->new();
				$ids->set_scan_keys(scan_keys => 1);
				if($ids->detect_attacks(request => $params) > 0) {
					if($logger) {
						$logger->warn("$addr: IDS blocked connexion for ", $info->as_string());
					}
					$status{$addr} = 0;
					throw Error::Simple("$addr: IDS blocked connexion for " . $info->as_string());
				}
			}
		}

		if(defined($ENV{'HTTP_REFERER'})) {
			# Protect against Shellshocker
			require Data::Validate::URI;
			Data::Validate::URI->import();

			my $v = Data::Validate::URI->new();
			unless($v->is_uri($ENV{'HTTP_REFERER'})) {
				if($logger) {
					$logger->warn("$ENV{REMOTE_ADDR}: Blocked shellshocker for $ENV{HTTP_REFERER}");
				}
				$status{$addr} = 0;
				throw Error::Simple("$ENV{REMOTE_ADDR}: Blocked shellshocker for $ENV{HTTP_REFERER}");
			}
			if(($ENV{'HTTP_REFERER'} =~ /^http:\/\/keywords-monitoring-your-success.com\/try.php/) ||
			   ($ENV{'HTTP_REFERER'} =~ /^http:\/\/www.tcsindustry\.com\//) ||
			   ($ENV{'HTTP_REFERER'} =~ /^http:\/\/free-video-tool.com\//)) {
				if($logger) {
					$logger->warn("$ENV{REMOTE_ADDR}: Blocked trawler");
				}
				$status{$addr} = 0;
				throw Error::Simple("$ENV{REMOTE_ADDR}: Blocked trawler");
			}
		}
	}

	require DateTime;
	DateTime->import();

	my @ips;
	my $today = DateTime->today()->ymd();
	my $readfromcache;

	my $cache = $args{'cache'};
	if(!defined($cache)) {
		throw Error::Simple('Either cache or config must be given') unless($args{config});
		$cache = ::create_memory_cache(config => $args{'config'}, namespace => __PACKAGE__, logger => $logger);
	}
	if(defined($cache)) {
		my $cachecontent = $cache->get($today);
		if($cachecontent) {
			if($logger) {
				$logger->debug("read from cache $cachecontent");
			}
			@ips = split(/,/, $cachecontent);
			$readfromcache = 1;
		} elsif($logger) {
			$logger->debug("Can't find $today in the cache");
		}
	} elsif($logger) {
		$logger->warn('Couldn\'t create the DShield cache');
	}

	unless($ips[0]) {
		require LWP::Simple;
		LWP::Simple->import();
		require XML::LibXML;
		XML::LibXML->import();

		if($logger) {
			$logger->trace('Downloading DShield signatures');
		}
		my $xml;
		eval {
			$xml = XML::LibXML->load_xml(string => get('https://secure.dshield.org/api/sources/attacks/100/2012-03-08'));
		};
		unless($@ || !defined($xml)) {
			foreach my $source ($xml->findnodes('/sources/data')) {
				my $lastseen = $source->findnodes('./lastseen')->to_literal();
				next unless($lastseen eq $today);  # FIXME: Should be today or yesterday to avoid midnight rush
				my $ip = $source->findnodes('./ip')->to_literal();
				$ip =~ s/0*(\d+)/$1/g;	# Perl interprets numbers leading with 0 as octal
				push @ips, $ip;
			}
			if(defined($cache) && !$readfromcache) {
				my $cachecontent = join(',', @ips);
				if($logger) {
					$logger->info("Setting DShield cache for $today to $cachecontent");
				}
				$cache->set($today, $cachecontent, '1 day');
			}
		}
	}

	# FIXME: Doesn't realise 1.2.3.4 is the same as 001.002.003.004
	if(grep($_ eq $ENV{'REMOTE_ADDR'}, @ips)) {
		if($logger) {
			$logger->warn("Dshield blocked connexion from $ENV{REMOTE_ADDR}");
		}
		$status{$addr} = 0;
		throw Error::Simple("Dshield blocked connexion from $ENV{REMOTE_ADDR}");
	}

	if($info->get_cookie(cookie_name => 'mycustomtrackid')) {
		if($logger) {
			$logger->warn('Blocking possible jqic');
		}
		$status{$addr} = 0;
		throw Error::Simple('Blocking possible jqic');
	}

	if($logger) {
		$logger->trace("Allowing connexion from $ENV{REMOTE_ADDR}");
	}

	$status{$addr} = 1;
	return 1;
}

1;
