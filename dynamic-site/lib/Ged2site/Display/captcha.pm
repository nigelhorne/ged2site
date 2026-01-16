package Ged2site::Display::captcha;

use strict;
use warnings;
use parent 'Ged2site::Display';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $config = $self->{'config'} or die "Missing 'config' handle";
	my $info = $self->{'info'} or die "Missing 'info' handle";

	# Get reCAPTCHA configuration
	my $recaptcha_config = $config->recaptcha();
	unless ($recaptcha_config && $recaptcha_config->{enabled}) {
		die 'reCAPTCHA is not enabled in configuration';
	}

	my $site_key = $recaptcha_config->{site_key};
	my $script_name = $ENV{'SCRIPT_NAME'} || '/cgi-bin/page.fcgi';

	# Get rate limit info for display
	my $soft_limit = $config->{'security'}->{'rate_limiting'}->{'max_requests'} || 100;
	my $time_window = $config->{'security'}->{'rate_limiting'}->{'time_window'} || '60s';
	$time_window =~ s/s$//;	# Remove 's' suffix

	# Determine if this is a hard block or soft limit
	my $is_hard_block = $args{'hard_block'} || 0;
	my $request_count = $args{'request_count'} || 0;

	if ($self->{'logger'}) {
		$self->{'logger'}->debug("Displaying CAPTCHA page for " . ($is_hard_block ? "hard block" : "soft limit"));
	}

	return $self->SUPER::html({
		site_key => $site_key,
		script_name => $script_name,
		soft_limit => $soft_limit,
		time_window => $time_window,
		is_hard_block => $is_hard_block,
		request_count => $request_count,
	});
}

1;
