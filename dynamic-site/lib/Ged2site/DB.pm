package Ged2site::DB;

=head1

Ged2site::DB

=cut

# Author Nigel Horne: njh@bandsman.co.uk
# Copyright (C) 2015-2022, Nigel Horne

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

# Abstract class giving read-only access to CSV, XML and SQLite databases via Perl without writing any SQL.
# Look for databases in $directory in this order;
#	SQLite (file ends with .sql)
#	PSV (pipe separated file, file ends with .psv)
#	CSV (file ends with .csv or .db, can be gzipped)
#	XML (file ends with .xml)

# For example, you can access the files in /var/db/foo.csv via this class:

# package MyPackageName::DB::foo;

# use NJH::Snippets::DB;

# our @ISA = ('NJH::Snippets::DB');

# 1;

# You can then access the data using:
# my $foo = MyPackageName::DB::foo->new(directory => '/var/db');
# my $row = $foo->fetchrow_hashref(customer_id => '12345);
# print Data::Dumper->new([$row])->Dump();

# CSV files can have empty lines of comment lines starting with '#', to make them more readable

# If the table has a column called "entry", sorts are based on that
# To turn that off, pass 'no_entry' to the constructor, for legacy
# reasons it's enabled by default
# TODO: Switch that to off by default, and enable by passing 'entry'

# TODO: support a directory hierarchy of databases
# TODO: consider returning an object or array of objects, rather than hashes
# TODO:	Add redis database - could be of use for Geo::Coder::Free
#	use select() to select a database - use the table arg
#	new(database => 'redis://servername');

use warnings;
use strict;

use DBD::SQLite::Constants qw/:file_open/;	# For SQLITE_OPEN_READONLY
use File::Basename;
use File::Spec;
use File::pfopen 0.02;
use File::Temp;
use Error::Simple;
use Error::DB::Open;
use Carp;

our $directory;
our $logger;
our $cache;

sub new {
	my $proto = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $class = ref($proto) || $proto;

	if($class eq __PACKAGE__) {
		croak("$class: abstract class");
	}

	croak("$class: where are the files?") unless($directory || $args{'directory'});
	# init(\%args);

	return bless {
		logger => $args{'logger'} || $logger,
		directory => $args{'directory'} || $directory,	# The directory containing the tables in XML, SQLite or CSV format
		cache => $args{'cache'} || $cache,
		table => $args{'table'},	# The name of the file containing the table, defaults to the class name
		no_entry => $args{'no_entry'} || 0,
	}, $class;
}

# Can also be run as a class level __PACKAGE__::DB::init(directory => '../databases')
sub init {
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	$directory ||= $args{'directory'};
	$logger ||= $args{'logger'};
	$cache ||= $args{'cache'};
}

sub set_logger {
	my $self = shift;

	my %args;

	if(ref($_[0]) eq 'HASH') {
		%args = %{$_[0]};
	} elsif(!ref($_[0])) {
		Carp::croak('Usage: set_logger(logger => $logger)');
	} elsif(scalar(@_) % 2 == 0) {
		%args = @_;
	} else {
		$args{'logger'} = shift;
	}

	$self->{'logger'} = $args{'logger'};

	return $self;
}

# Open the database.

sub _open {
	my $self = shift;
	my %args = (
		sep_char => '!',
		((ref($_[0]) eq 'HASH') ? %{$_[0]} : @_)
	);

	my $table = $self->{'table'} || ref($self);
	$table =~ s/.*:://;

	if($self->{'logger'}) {
		$self->{'logger'}->trace("_open $table");
	}
	return if($self->{$table});

	# Read in the database
	my $dbh;

	my $dir = $self->{'directory'} || $directory;
	my $slurp_file = File::Spec->catfile($dir, "$table.sql");
	if($self->{'logger'}) {
		$self->{'logger'}->debug("_open: try to open $slurp_file");
	}

	if(-r $slurp_file) {
		require DBI;

		DBI->import();

		$dbh = DBI->connect("dbi:SQLite:dbname=$slurp_file", undef, undef, {
			sqlite_open_flags => SQLITE_OPEN_READONLY,
		});
		$dbh->do('PRAGMA synchronous = OFF');
		$dbh->do('PRAGMA cache_size = 65536');
		if($self->{'logger'}) {
			$self->{'logger'}->debug("read in $table from SQLite $slurp_file");
		}
		$self->{'type'} = 'DBI';
	} else {
		my $fin;
		($fin, $slurp_file) = File::pfopen::pfopen($dir, $table, 'csv.gz:db.gz');
		if(defined($slurp_file) && (-r $slurp_file)) {
			require Gzip::Faster;
			Gzip::Faster->import();

			close($fin);
			$fin = File::Temp->new(SUFFIX => '.csv', UNLINK => 0);
			print $fin gunzip_file($slurp_file);
			$slurp_file = $fin->filename();
			$self->{'temp'} = $slurp_file;
		} else {
			($fin, $slurp_file) = File::pfopen::pfopen($dir, $table, 'psv');
			if(defined($fin)) {
				# Pipe separated file
				$args{'sep_char'} = '|';
			} else {
				($fin, $slurp_file) = File::pfopen::pfopen($dir, $table, 'csv:db');
			}
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
							},
						},
					}
				);
			} else {
				$dbh = DBI->connect("dbi:CSV:csv_sep_char=$sep_char");
			}
			$dbh->{'RaiseError'} = 1;

			if($self->{'logger'}) {
				$self->{'logger'}->debug("read in $table from CSV $slurp_file");
			}

			$dbh->{csv_tables}->{$table} = {
				allow_loose_quotes => 1,
				blank_is_undef => 1,
				empty_is_undef => 1,
				binary => 1,
				f_file => $slurp_file,
				escape_char => '\\',
				sep_char => $sep_char,
				# Don't do this, causes "Bizarre copy of HASH
				#	in scalar assignment in error_diag
				#	RT121127
				# auto_diag => 1,
				auto_diag => 0,
				# Don't do this, it causes "Attempt to free unreferenced scalar"
				# callbacks => {
					# after_parse => sub {
						# my ($csv, @rows) = @_;
						# my @rc;
						# foreach my $row(@rows) {
							# if($row->[0] !~ /^#/) {
								# push @rc, $row;
							# }
						# }
						# return @rc;
					# }
				# }
			};

			# my %options = (
				# allow_loose_quotes => 1,
				# blank_is_undef => 1,
				# empty_is_undef => 1,
				# binary => 1,
				# f_file => $slurp_file,
				# escape_char => '\\',
				# sep_char => $sep_char,
			# );

			# $dbh->{csv_tables}->{$table} = \%options;
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

			# Ignore blank lines or lines starting with # in the CSV file
			unless($self->{no_entry}) {
				@data = grep { $_->{'entry'} !~ /^\s*#/ } grep { defined($_->{'entry'}) } @data;
			}
			# $self->{'data'} = @data;
			my $i = 0;
			$self->{'data'} = ();
			foreach my $d(@data) {
				$self->{'data'}[$i++] = $d;
			}
			$self->{'type'} = 'CSV';
		} else {
			$slurp_file = File::Spec->catfile($dir, "$table.xml");
			if(-r $slurp_file) {
				$dbh = DBI->connect('dbi:XMLSimple(RaiseError=>1):');
				$dbh->{'RaiseError'} = 1;
				if($self->{'logger'}) {
					$self->{'logger'}->debug("read in $table from XML $slurp_file");
				}
				$dbh->func($table, 'XML', $slurp_file, 'xmlsimple_import');
			} else {
				throw Error::DB::Open(-file => $slurp_file);
			}
			$self->{'type'} = 'XML';
		}
	}

	$self->{$table} = $dbh;
	my @statb = stat($slurp_file);
	$self->{'_updated'} = $statb[9];

	return $self;
}

# Returns a reference to an array of hash references of all the data meeting
# the given criteria
sub selectall_hashref {
	my $self = shift;
	my @rc = $self->selectall_hash(@_);
	return \@rc;
}

# Returns an array of hash references
sub selectall_hash {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $table = $self->{table} || ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	if((scalar(keys %params) == 0) && $self->{'data'}) {
		if($self->{'logger'}) {
			$self->{'logger'}->trace("$table: selectall_hash fast track return");
		}
		# This use of a temporary variable is to avoid
		#	"Implicit scalar context for array in return"
		# return @{$self->{'data'}};
		my @rc = @{$self->{'data'}};
		return @rc;
	}
	# if((scalar(keys %params) == 1) && $self->{'data'} && defined($params{'entry'})) {
	# }

	my $query;
	my $done_where = 0;
	if(($self->{'type'} eq 'CSV') && !$self->{no_entry}) {
		$query = "SELECT * FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
		$done_where = 1;
	} else {
		$query = "SELECT * FROM $table";
	}
	my @query_args;
	foreach my $c1(sort keys(%params)) {	# sort so that the key is always the same
		my $arg = $params{$c1};
		if(ref($arg)) {
			if($self->{'logger'}) {
				$self->{'logger'}->fatal("selectall_hash $query: argument is not a string");
			}
			throw Error::Simple("$query: argument is not a string");
		}
		if(!defined($arg)) {
			my @call_details = caller(0);
			throw Error::Simple("$query: value for $c1 is not defined in call from " .
				$call_details[2] . ' of ' . $call_details[1]);
		}
		if($done_where) {
			if($arg =~ /\@/) {
				$query .= " AND $c1 LIKE ?";
			} else {
				$query .= " AND $c1 = ?";
			}
		} else {
			if($arg =~ /\@/) {
				$query .= " WHERE $c1 LIKE ?";
			} else {
				$query .= " WHERE $c1 = ?";
			}
			$done_where = 1;
		}
		push @query_args, $arg;
	}
	if(!$self->{no_entry}) {
		$query .= ' ORDER BY entry';
	}
	if(!wantarray) {
		$query .= ' LIMIT 1';
	}
	if($self->{'logger'}) {
		if(defined($query_args[0])) {
			$self->{'logger'}->debug("selectall_hash $query: ", join(', ', @query_args));
		} else {
			$self->{'logger'}->debug("selectall_hash $query");
		}
	}
	my $key;
	my $c;
	if($c = $self->{cache}) {
		$key = $query;
		if(defined($query_args[0])) {
			$key .= ' ' . join(', ', @query_args);
		}
		if(my $rc = $c->get($key)) {
			# This use of a temporary variable is to avoid
			#	"Implicit scalar context for array in return"
			# return @{$rc};
			my @rc = @{$rc};
			return @rc;
		}
	}

	if(my $sth = $self->{$table}->prepare($query)) {
		$sth->execute(@query_args) ||
			throw Error::Simple("$query: @query_args");

		my @rc;
		while(my $href = $sth->fetchrow_hashref()) {
			# FIXME: Doesn't store in the cache
			return $href if(!wantarray);
			push @rc, $href;
		}
		if($c && wantarray) {
			$c->set($key, \@rc, '1 hour');
		}

		return @rc;
	}
	if($self->{'logger'}) {
		$self->{'logger'}->warn("selectall_hash failure on $query: @query_args");
	}
	throw Error::Simple("$query: @query_args");
}

# Returns a hash reference for one row in a table
# Special argument: table: determines the table to read from if not the default,
#	which is worked out from the class name
sub fetchrow_hashref {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $table = $self->{'table'} || ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	my $query = 'SELECT * FROM ';
	if(my $t = delete $params{'table'}) {
		$query .= $t;
	} else {
		$query .= $table;
	}
	my $done_where = 0;
	if(($self->{'type'} eq 'CSV') && !$self->{no_entry}) {
		$query .= " WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
		$done_where = 1;
	}
	my @query_args;
	foreach my $c1(sort keys(%params)) {	# sort so that the key is always the same
		if(my $arg = $params{$c1}) {
			if($done_where) {
				if($arg =~ /\@/) {
					$query .= " AND $c1 LIKE ?";
				} else {
					$query .= " AND $c1 = ?";
				}
			} else {
				if($arg =~ /\@/) {
					$query .= " WHERE $c1 LIKE ?";
				} else {
					$query .= " WHERE $c1 = ?";
				}
				$done_where = 1;
			}
			push @query_args, $arg;
		}
	}
	# $query .= ' ORDER BY entry LIMIT 1';
	$query .= ' LIMIT 1';
	if($self->{'logger'}) {
		if(defined($query_args[0])) {
			my @call_details = caller(0);
			$self->{'logger'}->debug("fetchrow_hashref $query: ", join(', ', @query_args),
				' called from ', $call_details[2], ' of ', $call_details[1]);
		} else {
			$self->{'logger'}->debug("fetchrow_hashref $query");
		}
	}
	my $key;
	if(defined($query_args[0])) {
		$key = "fetchrow $query " . join(', ', @query_args);
	} else {
		$key = "fetchrow $query";
	}
	my $c;
	if($c = $self->{cache}) {
		if(my $rc = $c->get($key)) {
			return $rc;
		}
	}
	my $sth = $self->{$table}->prepare($query) or die $self->{$table}->errstr();
	$sth->execute(@query_args) || throw Error::Simple("$query: @query_args");
	if($c) {
		my $rc = $sth->fetchrow_hashref();
		$c->set($key, $rc, '1 hour');
		return $rc;
	}
	return $sth->fetchrow_hashref();
}

# Execute the given SQL on the data
# In an array context, returns an array of hash refs,
#	in a scalar context returns a hash of the first row
sub execute {
	my $self = shift;
	my %args;

	if(ref($_[0]) eq 'HASH') {
		%args = %{$_[0]};
	} elsif(ref($_[0])) {
		Carp::croak('Usage: execute(query => $query)');
	} elsif(scalar(@_) % 2 == 0) {
		%args = @_;
	} else {
		$args{'query'} = shift;
	}

	Carp::croak('Usage: execute(query => $query)') unless(defined($args{'query'}));

	my $table = $self->{table} || ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	my $query = $args{'query'};
	if($self->{'logger'}) {
		$self->{'logger'}->debug("execute $query");
	}
	my $sth = $self->{$table}->prepare($query);
	$sth->execute() || throw Error::Simple($query);
	my @rc;
	while(my $href = $sth->fetchrow_hashref()) {
		return $href if(!wantarray);
		push @rc, $href;
	}

	return @rc;
}

# Time that the database was last updated
sub updated {
	my $self = shift;

	return $self->{'_updated'};
}

# Return the contents of an arbitrary column in the database which match the
#	given criteria
# Returns an array of the matches, or just the first entry when called in
#	scalar context

# Set distinct to 1 if you're after a unique list
sub AUTOLOAD {
	our $AUTOLOAD;
	my $column = $AUTOLOAD;

	$column =~ s/.*:://;

	return if($column eq 'DESTROY');

	my $self = shift or return;

	my $table = $self->{table} || ref($self);
	$table =~ s/.*:://;

	$self->_open() if(!$self->{$table});

	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $query;
	my $done_where = 0;
	if(wantarray && !delete($params{'distinct'})) {
		if(($self->{'type'} eq 'CSV') && !$self->{no_entry}) {
			$query = "SELECT $column FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
			$done_where = 1;
		} else {
			$query = "SELECT $column FROM $table";
		}
	} else {
		if(($self->{'type'} eq 'CSV') && !$self->{no_entry}) {
			$query = "SELECT DISTINCT $column FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
			$done_where = 1;
		} else {
			$query = "SELECT DISTINCT $column FROM $table";
		}
	}
	my @args;
	while(my ($key, $value) = each %params) {
		if(defined($value)) {
			if($done_where) {
				$query .= " AND $key = ?";
			} else {
				$query .= " WHERE $key = ?";
				$done_where = 1;
			}
			push @args, $value;
		} else {
			if($self->{'logger'}) {
				$self->{'logger'}->debug("AUTOLOAD params $key isn't defined");
			}
			if($done_where) {
				$query .= " AND $key IS NULL";
			} else {
				$query .= " WHERE $key IS NULL";
				$done_where = 1;
			}
		}
	}
	$query .= " ORDER BY $column";
	if(!wantarray) {
		$query .= ' LIMIT 1';
	}
	if($self->{'logger'}) {
		if(scalar(@args) && $args[0]) {
			$self->{'logger'}->debug("AUTOLOAD $query: ", join(', ', @args));
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
		unlink delete $self->{'temp'};
	}
	if(my $table = delete $self->{'table'}) {
		$table->finish();
	}
}

1;
