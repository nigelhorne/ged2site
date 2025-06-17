package Ged2site::Display::mailto;

use strict;
use warnings;

# Send an e-mail to the owner

use Ged2site::Display;

our @ISA = ('Ged2site::Display');
our $mailfrom;	# Throttle emails being sent

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allow = {
		'subject' => undef,
		'page' => 'mailto',
		'action' => 'send',
		'message' => undef,
		'yemail' => undef,
		'yname' => undef,
		'lang' => qr/^[A-Z]{2}/i,
		'fbclid' => qr/^[\w-]+$/i,	# Facebook info
		'gclid' => qr/^\w+$/i,	# Google info
		'lint_content' => qr/^\d$/,
	};
	my $params = $info->params({ allow => $allow });

	delete $params->{'page'};
	delete $params->{'lang'};
	delete $params->{'fbclid'};
	delete $params->{'gclid'};
	delete $params->{'lint_content'};

	# my $mailto = $args{'mailto'};
	my $contact = $self->{_config}->{'contact'};

	my $action = $params->{'action'};

	if(!defined($action)) {
		# First time through
		if(my $name = $contact->{'name'}) {
			return $self->SUPER::html({ name => $name });
		}
		return $self->SUPER::html({ error => 'Recipient not given' });
	}

	if($action eq 'initial_form') {
		return $self->SUPER::html();
	} elsif($action eq 'send_verification') {
		# send_verification_email();
		return $self->SUPER::html({ action => 'verification_sent' });
	} elsif($action eq 'compose') {
		# show_compose_form();
	} elsif($action eq 'send_email') {
		# send_final_email();
	} else {
		# show_error("Invalid action");
	}

	if(($action ne 'send') && ($action ne 'send_email')) {
		return $self->SUPER::html();
	}

	my $copy = { %{$params} };
	if(!defined($params->{'yname'})) {
		$copy->{'error'} = 'Please enter your name';
	} elsif(!defined($params->{'yemail'})) {
		$copy->{'error'} = 'Please enter your e-mail address';
	} elsif(!defined($params->{'message'})) {
		$copy->{'error'} = 'Please enter the message';
	} elsif(!defined($params->{'subject'})) {
		$copy->{'error'} = 'Please enter the subject';
	}
	my $yemail = $params->{'yemail'};
	my $yname = $params->{'yname'};
	if(!defined($copy->{'error'})) {
		if($yemail !~ /\@/) {
			$copy->{'error'} = "The email address $yemail is not valid. Please try again";
		} elsif(($yname !~ / /) || ($yname =~ /^The /i)) {
			$copy->{'error'} = 'Please enter your <i>full</i> name';
		}
	}

	if(defined($copy->{'error'})) {
		return $self->SUPER::html($copy);
	}

	my $name = $self->{_config}->{'contact'}->{'name'};
	my $email = $self->{_config}->{'contact'}->{'email'};

	if(!(defined($name) && defined($email))) {
		$copy->{'error'} = 'Can\'t find contact details in the configuration file';
		return $self->SUPER::html($copy);
	}

	$self->{_logger}->debug("sending e-mail to $name");

	open(my $fout, '|-', '/usr/sbin/sendmail -t');

	print $fout "To: \"$name\" <$email>\n",
		"From: \"$yname\" <$yemail>\n",
		"Cc: \"$yname\" <$yemail>\n";

	if(my $remote_addr = $ENV{'REMOTE_ADDR'}) {
		$mailfrom->{$remote_addr}++;
		if($mailfrom->{$remote_addr} >= 3) {
			$info->status(429);
			$copy->{'error'} = 'You have reached your limit for sending e-mails';
			$self->{_logger}->info("E-mail blocked from $yemail");
			return $self->SUPER::html($copy);
		}
	}

	my $site_title = $self->{_config}->{'SiteTitle'};

	if(ref($site_title)) {
		$site_title = $site_title->{'English'};
		if(ref($site_title) eq 'ARRAY') {
			$site_title = join(' ', @{$site_title});
		}
	}

	my $host_name = $info->host_name();
	print $fout "Sender: \"$site_title\" <webmaster\@$host_name>\n",
		'Return-Receipt-To: ', $yemail, "\n";

	if($ENV{'REMOTE_ADDR'}) {
		print $fout ('X-On-Behalf-Of: ', $ENV{'REMOTE_ADDR'}, "\n");
	}

	# if((!defined($params->{'entry'})) || ($params->{'entry'} !~ /Nigel.Horne/i)) {
		# # For testing
		# print $fout "Bcc: njh\@bandsman.co.uk\n";
	# }

	print $fout $params->{'subject'} ? "Subject: $params->{subject}\n\n" : "Subject: Mail sent via $site_title\n\n";

	print $fout $params->{'message'}, "\n\n", '-' x 50, "\n";

	print $fout "Sent from $site_title, ", $self->{_info}->domain_name(), ".\n",
		"This service is provided to allow 3rd parties to contact\n",
		"you without your email address appearing on your website.\n",
		"Please report any abuse of this service to us.\n";

	close($fout);

	$self->{_logger}->info("E-mail sent from $yemail to $email");

	return $self->SUPER::html({ action => 'sent' });
}

1;
