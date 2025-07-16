package Ged2site::Display::mailto;

use strict;
use warnings;

# Driver for the page to send an e-mail

use Ged2site::Display;
use Data::Dumper;
use Digest::SHA qw(sha256_hex);
# use Email::Simple;
# use Email::Sender::Simple qw(sendmail);
# use Email::Sender::Transport::SMTP;	# Gives "Your vendor has not defined SSLeay macro SSL2_MT_REQUEST_CERTIFICATE"

our @ISA = ('Ged2site::Display');
our $mailfrom;	# Throttle emails being sent

# Configuration
# my $SMTP_HOST = 'localhost';  # Change to your SMTP server
# my $SMTP_PORT = 25;	# Change to your SMTP port
my $FROM_EMAIL = 'noreply@nigelhorne.com';  # Change to your domain
my $BASE_URL = 'https://genealogy.nigelhorne.com/cgi-bin/page.fcgi';  # Change to your URL
my $DEBUG = 0;	# Set to 1 to enable debugging, 0 to disable

# Simple session storage (in production, use proper session management)
my $session_file = '/tmp/email_sessions.dat';
my $captcha_file = '/tmp/email_captchas.dat';

sub html {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $info = $self->{_info};
	my $allow = {
		'subject' => undef,
		'captcha_token' => qr/^[a-f0-9]{64}$/,
		'captcha_answer' => qr/^\d+$/,
		'page' => 'mailto',
		'action' => undef,
		'message' => undef,
		'token' => qr/^[a-f0-9]{64}$/,
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

	my $site_title = $self->{_config}->{'SiteTitle'};

	if(ref($site_title)) {
		$site_title = $site_title->{'English'};
		if(ref($site_title) eq 'ARRAY') {
			$site_title = join(' ', @{$site_title});
		}
	}

	if($action eq 'initial_form') {
		return $self->SUPER::html();
	} elsif($action eq 'send_verification') {
		# send_verification_email();
		my $email = $params->{'yemail'};
			my $name = $params->{'yname'};

		unless ($email && $name) {
			return $self->SUPER::html({ error => 'Please provide both email and name' });
		}

		# Generate verification token
		my $token = sha256_hex($email . time() . rand());

		# Store session data (in production, use proper database/session storage)
		store_session($token, { email => $email, name => $name, timestamp => time() });

		# Create verification link
		my $verify_link = "$BASE_URL?page=mailto&action=compose&token=$token";

		# Send verification email
		my $email_body = qq{
Hello $name,

Please click the link below to compose and send your email:

$verify_link

This link will expire in 1 hour.

Best regards,
Email Service
		};
		# eval {
			# my $email_obj = Email::Simple->create(
				# header => [
					# To      => $email,
					# From    => $FROM_EMAIL,
					# Subject => 'Email Service - Verification Link',
				# ],
				# body => $email_body,
			# );

			# Configure SMTP transport (adjust for your SMTP server)
			# my $transport = Email::Sender::Transport::SMTP->new({
				# host => $SMTP_HOST,
				# port => $SMTP_PORT,
			# });

			# sendmail($email_obj, { transport => $transport });
		# };

		# if ($@) {
			return $self->SUPER::html({ error => "Failed to send verification email $@" });
		# }

		if(open(my $fout, '|-', '/usr/sbin/sendmail -t')) {
			# print $fout "To: $email\n", 'From: "', $FROM_EMAIL, "\n";
			print $fout "To: $email\n";

			# my $host_name = $info->host_name();
			# print $fout "Sender: \"$site_title\" <webmaster\@$host_name>\n";

			# if((!defined($params->{'entry'})) || ($params->{'entry'} !~ /Nigel.Horne/i)) {
				# For testing
				# print $fout "Bcc: njh\@bandsman.co.uk\n";
			# }

			if($ENV{'REMOTE_ADDR'}) {
				print $fout 'X-On-Behalf-Of: ', $ENV{'REMOTE_ADDR'}, "\n";
			}

			print $fout "Subject: Email Service - Verification Link\n\n$email_body\n\n";

			print $fout "Sent from $site_title, ", $self->{_info}->domain_name(), ".\n",
				"This service is provided to allow 3rd parties to contact\n",
				"peopl without their email address appearing on the website.\n",
				"Please report any abuse of this service to us.\n";

			close $fout;
		}

		return $self->SUPER::html({ mail => $email });
	} elsif($action eq 'compose') {
		# show_compose_form();
	    my $token = $params->{'token'};

	    if ($DEBUG) {
		print STDERR "DEBUG: Token received: '$token'\n" if($token);
		print STDERR "DEBUG: Session file exists: " . (-f $session_file ? "YES" : "NO") . "\n";
		print STDERR "DEBUG: Session file path: $session_file\n";
	    }

	    unless ($token) {
		return $self->SUPER::html({ error => "Invalid verification link - no token provided" });
	    }

	    # Verify token and get session data
	    my $session_data = get_session($token);

	    if ($DEBUG) {
		print STDERR "DEBUG: Session data retrieved: " . (defined $session_data ? "YES" : "NO") . "\n";
		if ($session_data) {
		    print STDERR "DEBUG: Session contains: email=" . ($session_data->{email} || "UNDEF") .
				", name=" . ($session_data->{name} || "UNDEF") .
				", timestamp=" . ($session_data->{timestamp} || "UNDEF") . "\n";
		}
	    }

	    unless ($session_data) {
		return $self->SUPER::html({ error => "Invalid or expired verification link - session not found" });
	    }

	    # Check if token is expired (1 hour)
	    my $age = time() - $session_data->{timestamp};
	    if ($DEBUG) {
		print STDERR "DEBUG: Session age: $age seconds (expires at 3600)\n";
	    }

	    if ($age > 3600) {
		return $self->SUPER::html({ error => "Verification link has expired (age: " . int($age/60) . " minutes)" });
	    }

		# Optional: Delete token immediately after first use (makes link single-use)
		# Uncomment the next line if you want single-use verification links
		delete_session($token);

		return $self->SUPER::html({ token => $token, session_data => $session_data });
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

sub store_session {
	my ($token, $data) = @_;

    my $sessions = {};
    if (-f $session_file) {
	eval {
	    open my $fh, '<', $session_file or die "Can't read session file: $!";
	    local $/;
	    my $content = <$fh>;
	    close $fh;
	    if ($content && $content =~ /\S/) {
		my $VAR1;  # For Data::Dumper output
		$sessions = eval $content;
		$sessions = {} unless ref $sessions eq 'HASH';
	    }
	};
	# If eval fails, start with empty sessions hash
	$sessions = {} if $@;
    }

    $sessions->{$token} = $data;

    # Use a more reliable serialization method
    eval {
	open my $fh, '>', $session_file or die "Can't write session file: $!";
	my $dumper = Data::Dumper->new([$sessions]);
	$dumper->Purity(1);
	$dumper->Terse(1);
	print $fh $dumper->Dump();
	close $fh;
	chmod 0600, $session_file;  # Secure the file
    };
	die "Failed to store session: $@" if $@;
}

sub get_session {
	my $token = shift;

    return undef unless -f $session_file;
    return undef unless $token;

    my $sessions = {};
    eval {
	open my $fh, '<', $session_file or die "Can't read session file: $!";
	local $/;
	my $content = <$fh>;
	close $fh;

	if ($content && $content =~ /\S/) {
	    my $VAR1;  # For Data::Dumper output
	    $sessions = eval $content;
	    $sessions = {} unless ref $sessions eq 'HASH';
	}
    };

    # Return undef if there was an error or token doesn't exist
    return undef if $@ || !exists $sessions->{$token};
    return $sessions->{$token};
}

sub delete_session {
	my $token = shift;

    return unless -f $session_file;
    return unless $token;

    my $sessions = {};
    eval {
	open my $fh, '<', $session_file or die "Can't read session file: $!";
	local $/;
	my $content = <$fh>;
	close $fh;

	if ($content && $content =~ /\S/) {
	    my $VAR1;  # For Data::Dumper output
	    $sessions = eval $content;
	    $sessions = {} unless ref $sessions eq 'HASH';
	}
    };

    return if $@;

    delete $sessions->{$token};

    eval {
	open my $fh, '>', $session_file or die "Can't write session file: $!";
	my $dumper = Data::Dumper->new([$sessions]);
	$dumper->Purity(1);
	$dumper->Terse(1);
	print $fh $dumper->Dump();
	close $fh;
	};
}

1;
