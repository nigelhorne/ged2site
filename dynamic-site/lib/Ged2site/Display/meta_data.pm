package Ged2site::Display::meta_data;

# Display the meta-data page - the internal status of the server and Ged2site system

use strict;
use warnings;

use parent 'Ged2site::Display';

use Filesys::Df;
use List::Util qw(max);
use POSIX qw(strftime);
use System::Info;
use Sys::Uptime;
use Sys::MemInfo;
use Time::Piece;
use Time::Seconds;

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $vwf_log = $args{'vwf_log'} or die "Missing 'vwf_log' handle";
	my $domain_name = $self->{'info'}->domain_name();

	# --- Browser breakdown for existing chart ---
	my $datapoints;
	foreach my $type ('web','mobile','search','robot') {
		my @entries = $vwf_log->type({ domain_name => $domain_name, type => $type });
		$datapoints .= '{y: ' . scalar(@entries) . ", label: \"$type\"},\n";
		if($self->{'logger'}) {
			$self->{'logger'}->debug("$type = " . scalar(@entries));
		}
	}

	# --- Server metrics using CPAN modules ---
	my $server_metrics = $self->get_server_metrics();

	# --- Traffic metrics from vwf_log ---
	my $traffic_metrics = $self->get_traffic_metrics($vwf_log, $domain_name);

	# --- HTTP status breakdown for pie chart ---
	my $status_datapoints;
	my %status_count;
	foreach my $http_code ($vwf_log->http_code({ domain_name => $domain_name })) {
		$status_count{$http_code}++;
	}

	foreach my $code (sort keys %status_count) {
		$status_datapoints .= '{y: ' . $status_count{$code} . ", label: \"$code\"},\n";
	}

	my $rate_24h = $self->get_request_rate_24h($vwf_log, $domain_name);
	my $latency_24h = $self->get_latency_24h($vwf_log, $domain_name);

	return $self->SUPER::html({
		datapoints => $datapoints,
		server => $server_metrics,
		traffic => $traffic_metrics,
		status_dp => $status_datapoints,
		rate_total_dp => $rate_24h->{total_dp},
		rate_error_dp => $rate_24h->{error_dp},
		rate_error_pct_dp => $rate_24h->{error_pct_dp},
		latency_avg_dp => $latency_24h->{avg_dp},
		latency_p95_dp => $latency_24h->{p95_dp},
		slow_dp => $self->get_slow_endpoints_24h($vwf_log, $domain_name),
	});
}

sub get_server_metrics {
	my $metrics = {};

	# CPU info
	my $si = System::Info->new;
	$metrics->{cpu_count} = $si->ncpu // 0;
	$metrics->{cpu_type} = $si->cpu_type // '';

	# Disk usage
	if(my $df = df('/')) {
		# prefer 'per' if present
		$metrics->{disk_used_pct} = $df->{per} // int(100 * ($df->{blocks} - $df->{bfree}) / $df->{blocks});
	} else {
		$metrics->{disk_used_pct} = undef;
	}

	# Memory usage (via Sys::MemInfo)
	my $total_mem = Sys::MemInfo::totalmem();
	my $free_mem = Sys::MemInfo::freemem();
	if (defined $total_mem && defined $free_mem && $total_mem > 0) {
		$metrics->{memory_used_pct} = int(100 * ($total_mem - $free_mem) / $total_mem);
	} else {
		$metrics->{memory_used_pct} = 0;
	}

	return $metrics;
}

# ------------------------------
# Traffic metrics from vwf_log
# ------------------------------

sub get_traffic_metrics {
	my ($self, $vwf_log, $domain_name) = @_;
	my $metrics = {};

	# Current time and one hour ago (local time)
	my $now = time();
	my $hour_ago = $now - ONE_HOUR + _utc_offset();

	# Get all entries as array of hashrefs
	my @entries = $vwf_log->selectall_array({ domain_name => $domain_name });

	# Filter entries from last hour
	my @recent;
	foreach my $entry (@entries) {
		next unless ref $entry eq 'HASH' && $entry->{time};

		my $tp;
		eval { $tp = Time::Piece->strptime($entry->{time}, '%Y-%m-%d %H:%M:%S') };
		next unless $tp;

		my $epoch = $tp->epoch;
		push @recent, $entry if $epoch > $hour_ago;
	}

	# Requests per hour
	$metrics->{requests_per_hour} = scalar @recent;

	# Active users (unique IPs)
	my %ips;
	foreach my $entry (@recent) {
		my $ip = $entry->{ip} // 'unknown';
		$ips{$ip} = 1;
	}
	$metrics->{active_users} = scalar keys %ips;

	# Top 5 endpoints
	# my %urls;
	# foreach my $entry (@recent) {
		# my $url = $entry->{url} // '/';
		# $urls{$url}++;
	# }
	# my @top_urls = sort { $urls{$b} <=> $urls{$a} } keys %urls;
	# $metrics->{top_urls} = [ @top_urls[0..(4 > $#top_urls ? $#top_urls : 4)] ];

	# Error count (HTTP code >= 400)
	my $errors = grep { ($_->{http_code} // 0) >= 400 } @recent;
	$metrics->{errors_last_hour} = $errors;

	return $metrics;
}

sub get_request_rate_24h {
	my ($self, $vwf_log, $domain_name) = @_;

	my $now = time();
	my $start = $now - ONE_DAY + _utc_offset();

	my %buckets;

	foreach my $entry ($vwf_log->selectall_array({ domain_name => $domain_name })) {
		next unless ref $entry eq 'HASH' && $entry->{time};

		my $tp;
		eval { $tp = Time::Piece->strptime($entry->{time}, '%Y-%m-%d %H:%M:%S') };
		next unless $tp;

		my $epoch = $tp->epoch;
		next if $epoch < $start;

		# Bucket by hour
		my $bucket = $tp->strftime('%H:00');

		$buckets{$bucket}{total}++;
		if(($entry->{http_code} // 0) >= 400) {
			$buckets{$bucket}{errors}++;
		}
	}

	# Build CanvasJS datapoints
	my (@total_dp, @error_dp, @error_pct_dp);

	foreach my $hour (sort keys %buckets) {
		my $total = $buckets{$hour}{total} // 0;
		my $errors = $buckets{$hour}{errors} // 0;

		push @total_dp,
		sprintf('{ label: "%s", y: %d }', $hour, $total);

		push @error_dp,
		sprintf('{ label: "%s", y: %d }', $hour, $errors);

		my $pct = $total ? sprintf('%.2f', ($errors / $total) * 100) : 0;
		push @error_pct_dp,
		sprintf('{ label: "%s", y: %s }', $hour, $pct);
	}

	return {
		total_dp => join(",\n", @total_dp),
		error_dp => join(",\n", @error_dp),
		error_pct_dp => join(",\n", @error_pct_dp),
	};
}

sub get_latency_24h {
	my ($self, $vwf_log, $domain_name) = @_;

	my $start = time() - ONE_DAY + _utc_offset();

	my %buckets;

	foreach my $entry ($vwf_log->selectall_array({ domain_name => $domain_name })) {
		next unless ref $entry eq 'HASH';
		next unless $entry->{time};
		next unless exists $entry->{duration_ms};

		my $tp;
		eval { $tp = Time::Piece->strptime($entry->{time}, '%Y-%m-%d %H:%M:%S') };
		next unless $tp;

		my $epoch = $tp->epoch;
		next if $epoch < $start;

		my $hour = $tp->strftime('%H:00');

		push @{ $buckets{$hour} }, $entry->{duration_ms};
	}

	my (@avg_dp, @p95_dp);

	foreach my $hour (sort keys %buckets) {
		my @vals = sort { $a <=> $b } @{ $buckets{$hour} };
		next unless @vals;

		my $count = @vals;
		my $avg = int((eval(join('+', @vals)) || 0) / $count);

		my $p95_index = int(0.95 * ($count - 1));
		my $p95 = $vals[$p95_index];

		push @avg_dp,
		sprintf('{ label: "%s", y: %d }', $hour, $avg);

		push @p95_dp,
		sprintf('{ label: "%s", y: %d }', $hour, $p95);
	}

	return {
		avg_dp => join(",\n", @avg_dp),
		p95_dp => join(",\n", @p95_dp),
	};
}

sub get_slow_endpoints_24h {
	my ($self, $vwf_log, $domain_name) = @_;

	my $start = time() - ONE_DAY + _utc_offset();

	# Step 1: fetch rows filtered only by equality
	my @rows = $vwf_log->selectall_array({ domain_name => $domain_name });

	# Step 2: bucket in Perl
	my %stats;

	foreach my $row (@rows) {
		next unless defined $row->{time};
		next unless defined $row->{duration_ms};

		my $tp;
		eval { $tp = Time::Piece->strptime($row->{time}, '%Y-%m-%d %H:%M:%S') };
		next unless $tp;

		next if $tp->epoch < $start;

		my $tpl = $row->{template} // '';
		$stats{$tpl}{hits}++;
		$stats{$tpl}{total_ms} += $row->{duration_ms};
	}

	# Step 3: compute averages + threshold
	my @ranked;
	foreach my $tpl (keys %stats) {
		next if $stats{$tpl}{hits} < 5;

		push @ranked, {
			template => $tpl,
			avg_ms => $stats{$tpl}{total_ms} / $stats{$tpl}{hits},
		};
	}

	# Step 4: sort + top 10
	@ranked = sort { $b->{avg_ms} <=> $a->{avg_ms} } @ranked;
	splice(@ranked, 10) if @ranked > 10;

	# Step 5: CanvasJS datapoints
	my @dp;
	foreach my $row (@ranked) {
		my $label = $row->{template};
		$label =~ s/"/\\"/g;

		push @dp, sprintf(
			'{ label: "%s", y: %.0f }',
			$label,
			$row->{avg_ms}
		);
	}

	return join(', ', @dp);
}

sub _utc_offset
{
	my $local_time = time();
	my @local = localtime($local_time);
	my @gmt = gmtime($local_time);

	# Convert both to seconds since midnight
	my $local_seconds = $local[2] * 3600 + $local[1] * 60 + $local[0];
	my $gmt_seconds = $gmt[2] * 3600 + $gmt[1] * 60 + $gmt[0];

	# Account for day boundary crossing
	my $day_diff = $local[3] - $gmt[3];
	if ($day_diff > 1) { $day_diff = -1; }	# wrapped backwards
	if ($day_diff < -1) { $day_diff = 1; }	# wrapped forwards

	return $local_seconds - $gmt_seconds + ($day_diff * 86400);
}

1;
