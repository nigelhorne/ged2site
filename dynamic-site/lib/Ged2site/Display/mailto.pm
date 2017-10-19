package Ged2site::Display::mailto;

use strict;
use warnings;

# Send an e-mail to the owner

use Ged2site::Display;

our @ISA = ('Ged2site::Display');

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allowed = {
		'subject' => undef,
		'page' => 'mailto',
		'action' => 'send',
		'message' => undef,
		'yemail' => undef,
		'yname' => undef,
		'lang' => qr/^[A-Z][A-Z]/i,
	};
	my $params = $info->params({ allow => $allowed });

	# my $mailto = $args{'mailto'};
	my $contact = $self->{_config}->{'contact'};

	if(!defined($params->{'action'})) {
		# First time through
		if(my $name = $contact->{'name'}) {
			return $self->SUPER::html({ name => $name });
		}
		return $self->SUPER::html({ error => 'Recipient not given' });
	}

	if($params->{'action'} ne 'send') {
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

	my $site_title = $self->{_config}->{'SiteTitle'};

	if(ref($site_title)) {
		$site_title = $site_title->{'English'};
		if(ref($site_title) eq 'ARRAY') {
			$site_title = join(' ', @{$site_title});
		}
	}

	print $fout "Sender: $site_title\n",
		'Return-Receipt-To: ', $yemail, "\n";

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
