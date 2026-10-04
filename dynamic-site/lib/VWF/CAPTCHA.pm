package VWF::CAPTCHA;

use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

sub new {
	my ($class, %args) = @_;

	my $self = {
		site_key => $args{site_key} || die 'site_key required',
		secret_key => $args{secret_key} || die 'secret_key required',
		logger => $args{logger},
	};

	return bless $self, $class;
}

sub verify {
	my ($self, $response_token, $remote_ip) = @_;

	return 0 unless $response_token;

	my $ua = LWP::UserAgent->new(timeout => 10);

	my $response = $ua->post('https://www.google.com/recaptcha/api/siteverify', {
		secret => $self->{secret_key},
		response => $response_token,
		remoteip => $remote_ip,
	});

	unless ($response->is_success) {
		$self->{logger}->error("reCAPTCHA verification failed: " . $response->status_line) if $self->{logger};
		return 0;
	}

	my $result = decode_json($response->decoded_content());

	if ($result->{success}) {
		$self->{logger}->info("reCAPTCHA verification successful for $remote_ip") if $self->{logger};
		return 1;
	}

	$self->{logger}->warn("reCAPTCHA verification failed for $remote_ip: " . join(', ', @{$result->{'error-codes'} || []}))
		if $self->{logger};

	return 0;
}

sub get_site_key {
	my $self = $_[0];
	return $self->{site_key};
}

1;
