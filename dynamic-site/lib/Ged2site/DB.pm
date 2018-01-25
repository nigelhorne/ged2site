package Ged2site::DB;

# Author Nigel Horne: njh@bandsman.co.uk
# Copyright (C) 2015-2018, Nigel Horne

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

# Read-only access to databases

use warnings;
use strict;

use File::Basename;
use DBI;
use File::Spec;
use File::pfopen 0.02;
use File::Temp;
use Gzip::Faster;
use DBD::SQLite::Constants qw/:file_open/;	# For SQLITE_OPEN_READONLY
use Error::Simple;

our @databases;
our $directory;
our $logger;
our $cache;

sub new {
	my $proto = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $class = ref($proto) || $proto;

	if($class eq 'Ged2site::DB') {
		die "$class: abstract class";
	}

	die "$class: where are the files?" unless($directory || $args{'directory'});
	# init(\%args);

	return bless {
		logger => $args{'logger'} || $logger,
		directory => $args{'directory'} || $directory,
		cache => $args{'cache'} || $cache
	}, $class;
}

# Can also be run as a class level Ged2site::DB::init(directory => '../databases')
sub init {
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	$directory ||= $args{'directory'};
	$logger ||= $args{'logger'};
	$cache ||= $args{'cache'};
	if($args{'databases'}) {
		@databases = $args{'databases'};
	}
	throw Error::Simple('directory not given') unless($directory);
}

sub set_logger {
	my $self = shift;

	my %args;

	if(ref($_[0]) eq 'HASH') {
		%args = %{$_[0]};
	} elsif(scalar(@_) % 2 == 0) {
		%args = @_;
	} else {
		$args{'logger'} = shift;
	}

	$self->{'logger'} = $args{'logger'};
}

sub _open {
	my $self = shift;
	my %args = (
		sep_char => '!',
		((ref($_[0]) eq 'HASH') ? %{$_[0]} : @_)
	);

	my $table = ref($self);
	$table =~ s/.*:://;

	if($self->{'logger'}) {
		$self->{'logger'}->trace("_open $table");
	}
	return if($self->{$table});

	# Read in the database
	my $dbh;

	my $directory = $self->{'directory'} || $directory;
	my $slurp_file = File::Spec->catfile($directory, "$table.sql");

	if(-r $slurp_file) {
		$dbh = DBI->connect("dbi:SQLite:dbname=$slurp_file", undef, undef, {
			sqlite_open_flags => SQLITE_OPEN_READONLY,
		});
		if($self->{'logger'}) {
			$self->{'logger'}->debug("read in $table from SQLite $slurp_file");
		}
	} else {
		my $fin;
		($fin, $slurp_file) = File::pfopen::pfopen($directory, $table, 'csv.gz:db.gz');
		if(defined($slurp_file) && (-r $slurp_file)) {
			$fin = File::Temp->new(SUFFIX => '.csv', UNLINK => 0);
			print $fin gunzip_file($slurp_file);
			$slurp_file = $fin->filename();
			$self->{'temp'} = $slurp_file;
		} else {
			($fin, $slurp_file) = File::pfopen::pfopen($directory, $table, 'csv:db');
		}
		if(defined($slurp_file) && (-r $slurp_file)) {
			close($fin);
			my $sep_char = $args{'sep_char'};
			if($args{'column_names'}) {
				$dbh = DBI->connect("dbi:CSV:csv_sep_char=$sep_char", undef, undef,
					{
						csv_tables => {
							$table => {
								col_names => $args{'column_names'},
							}
						}
					}
				);
			} else {
				$dbh = DBI->connect("dbi:CSV:csv_sep_char=$sep_char");
			}
			$dbh->{'RaiseError'} = 1;

			if($self->{'logger'}) {
				$self->{'logger'}->debug("read in $table from CSV $slurp_file");
			}

			my %options = (
				allow_loose_quotes => 1,
				blank_is_undef => 1,
				empty_is_undef => 1,
				binary => 1,
				f_file => $slurp_file,
				escape_char => '\\',
				sep_char => $sep_char,
			);

			$dbh->{csv_tables}->{$table} = \%options;
			# delete $options{f_file};

			# require Text::CSV::Slurp;
			# Text::CSV::Slurp->import();
			# $self->{'data'} = Text::CSV::Slurp->load(file => $slurp_file, %options);

			require Text::xSV::Slurp;
			Text::xSV::Slurp->import();

			my @data = @{xsv_slurp(
				shape => 'aoh',
				text_csv => {
					sep_char => $sep_char,
					allow_loose_quotes => 1,
					blank_is_undef => 1,
					empty_is_undef => 1,
					binary => 1,
					escape_char => '\\',
				},
				# string => \join('', grep(!/^\s*(#|$)/, <DATA>))
				file => $slurp_file
			)};

			# Don't use blank lines or comments
			@data = grep { $_->{'entry'} !~ /^#/ } grep { defined($_->{'entry'}) } @data;
			# $self->{'data'} = @data;
			my $i = 0;
			$self->{'data'} = ();
			foreach my $d(@data) {
				$self->{'data'}[$i++] = $d;
			}
		} else {
			$slurp_file = File::Spec->catfile($directory, "$table.xml");
			if(-r $slurp_file) {
				$dbh = DBI->connect('dbi:XMLSimple(RaiseError=>1):');
				$dbh->{'RaiseError'} = 1;
				if($self->{'logger'}) {
					$self->{'logger'}->debug("read in $table from XML $slurp_file");
				}
				$dbh->func($table, 'XML', $slurp_file, 'xmlsimple_import');
			} else {
				throw Error::Simple("Can't open $directory/$table");
			}
		}
	}

	push @databases, $table;

	$self->{$table} = $dbh;
	my @statb = stat($slurp_file);
	$self->{'_updated'} = $statb[9];
}

# Returns a reference to an array of hash references of all the data meeting
# the given criteria
sub selectall_hashref {
	my @rc = selectall_hash(@_);
	return \@rc;
}

# Returns an array of hash references
sub selectall_hash {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $table = ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	if((scalar(keys %args) == 0) && $self->{'data'}) {
		if($self->{'logger'}) {
			$self->{'logger'}->trace("$table: selectall_hash fast track return");
		}
		return @{$self->{'data'}};
	}

	my $query = "SELECT * FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
	my @args;
	foreach my $c1(keys(%args)) {
		$query .= " AND $c1 LIKE ?";
		push @args, $args{$c1};
	}
	$query .= ' ORDER BY entry';
	if($self->{'logger'}) {
		$self->{'logger'}->debug("selectall_hash $query: " . join(', ', @args));
	}
	my $sth = $self->{$table}->prepare($query);
	$sth->execute(@args) || throw Error::Simple("$query: @args");

	my $key = "$query " . join(', ', @args);
	my $c;
	if($c = $self->{cache}) {
		if(my $rc = $c->get($key)) {
			return @{$rc};
		}
	}
	my @rc;
	while(my $href = $sth->fetchrow_hashref()) {
		push @rc, $href;
		last if(!wantarray);
	}
	if($c && wantarray) {
		$c->set($key, \@rc, '1 hour');
	}

	return @rc;
}

# Returns a hash reference for one row in a table
sub fetchrow_hashref {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $table = ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{table});

	# Only want one row, so use distinct
	my $query = "SELECT DISTINCT * FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
	my @args;
	foreach my $c1(keys(%args)) {
		$query .= " AND $c1 LIKE ?";
		push @args, $args{$c1};
	}
	$query .= ' ORDER BY entry';
	if($self->{'logger'}) {
		$self->{'logger'}->debug("fetchrow_hashref $query: " . join(', ', @args));
	}
	my $sth = $self->{$table}->prepare($query);
	$sth->execute(@args) || throw Error::Simple("$query: @args");
	return $sth->fetchrow_hashref();
}

# Execute the given SQL on the data
sub execute {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $table = ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{table});

	my $query = $args{'query'};
	if($self->{'logger'}) {
		$self->{'logger'}->debug("fetchrow_hashref $query");
	}
	my $sth = $self->{$table}->prepare($query);
	$sth->execute() || throw Error::Simple($query);
	my @rc;
	while(my $href = $sth->fetchrow_hashref()) {
		push @rc, $href;
	}

	return \@rc;
}

# Time that the database was last updated
sub updated {
	my $self = shift;

	return $self->{'_updated'};
}

# Return the contents of an arbiratary column in the database which match the
#	given criteria
# Returns an array of the matches, or just the first entry when called in
#	scalar context

# Set distinct to 1 if you're after a uniq list
sub AUTOLOAD {
	our $AUTOLOAD;
	my $column = $AUTOLOAD;

	$column =~ s/.*:://;

	return if($column eq 'DESTROY');

	my $self = shift or return undef;

	my $table = ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $query;
	if(wantarray && !delete($params{'distinct'})) {
		$query = "SELECT $column FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
	} else {
		$query = "SELECT DISTINCT $column FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
	}
	my @args;
	foreach my $c1(keys(%params)) {
		if(!defined($params{$c1})) {
			$self->{'logger'}->debug("AUTOLOAD params $c1 isn't defined");
		}
		# $query .= " AND $c1 LIKE ?";
		$query .= " AND $c1 = ?";
		push @args, $params{$c1};
	}
	$query .= " ORDER BY $column";
	if($self->{'logger'}) {
		if(scalar(@args) && $args[0]) {
			$self->{'logger'}->debug("AUTOLOAD $query: " . join(', ', @args));
		} else {
			$self->{'logger'}->debug("AUTOLOAD $query");
		}
	}
	my $sth = $self->{$table}->prepare($query) || throw Error::Simple($query);
	$sth->execute(@args) || throw Error::Simple($query);

	if(wantarray) {
		return map { $_->[0] } @{$sth->fetchall_arrayref()};
	}
	return $sth->fetchrow_array();	# Return the first match only
}

sub DESTROY {
	if(defined($^V) && ($^V ge 'v5.14.0')) {
		return if ${^GLOBAL_PHASE} eq 'DESTRUCT';	# >= 5.14.0 only
	}
	my $self = shift;

	if($self->{'temp'}) {
		unlink $self->{'temp'};
	}
}

1;
