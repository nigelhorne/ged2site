package Ged2site::DB;

=head1 NAME

Ged2site::DB

=cut

# Author Nigel Horne: njh@bandsman.co.uk
# Copyright (C) 2015-2024, Nigel Horne

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

# use Ged2site::DB;

# our @ISA = ('Ged2site::DB');

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
our $cache_duration;

=head1 SUBROUTINES/METHODS

=head2 init

Set some class level defaults.

    __PACKAGE__::DB::init(directory => '../databases')

See the documentation for new() to see what variables can be set

=cut

sub init {
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	$directory ||= $args{'directory'};
	$logger ||= $args{'logger'};
	$cache ||= $args{'cache'};
	$cache_duration ||= $args{'cache_duration'};
}

=head2 new

Create an object to point to a read-only database.

Arguments:

cache => place to store results
cache_duration => how long to store results in the cache (default is 1 hour)
directory => where the database file is held

If the arguments are not set, tries to take from class level defaults

=cut

sub new {
	my $proto = shift;
        my %args;

        if(ref($_[0]) eq 'HASH') {
                %args = %{$_[0]};
        } elsif(scalar(@_) % 2 == 0) {
                %args = @_;
        } elsif(scalar(@_) == 1) {
                $args{'directory'} = shift;
        }

	my $class = ref($proto) || $proto;

	if(!defined($class)) {
		# Using Ged2site::DB->new(), not Ged2site::DB::new()
		carp(__PACKAGE__, ' use ->new() not ::new() to instantiate');
		return;
	} elsif($class eq __PACKAGE__) {
		croak("$class: abstract class");
	}

	croak("$class: where are the files?") unless($directory || $args{'directory'});
	# init(\%args);

	return bless {
		logger => $args{'logger'} || $logger,
		directory => $args{'directory'} || $directory,	# The directory containing the tables in XML, SQLite or CSV format
		cache => $args{'cache'} || $cache,
		cache_duration => $args{'cache_duration'} || $cache_duration || '1 hour',
		table => $args{'table'},	# The name of the file containing the table, defaults to the class name
		no_entry => $args{'no_entry'} || 0,
	}, $class;
}

sub set_logger
{
	my $self = shift;

	my %args;

	if(ref($_[0]) eq 'HASH') {
		%args = %{$_[0]};
	} elsif(scalar(@_) % 2 == 0) {
		%args = @_;
	} elsif((scalar(@_) == 1) && ref($_[0])) {
		$args{'logger'} = shift;
	}

	if(defined($args{'logger'})) {
		$self->{'logger'} = $args{'logger'};
		return $self;
	}
	Carp::croak('Usage: set_logger(logger => $logger)')
}

# Open the database.

# FIXME: The default separator character is (for my historical reasons) '!' not ','

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
			if($self->{'logger'}) {
				$self->{'logger'}->debug(__LINE__, ' of ', __PACKAGE__, ": slurp_file = $slurp_file, sep_char = $sep_char");
			}
			if($args{'column_names'}) {
				$dbh = DBI->connect("dbi:CSV:db_name=$slurp_file", undef, undef,
					{
						csv_sep_char => $sep_char,
						csv_tables => {
							$table => {
								col_names => $args{'column_names'},
							},
						},
					}
				);
			} else {
				$dbh = DBI->connect("dbi:CSV:db_name=$slurp_file", undef, undef, { csv_sep_char => $sep_char});
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

			# FIXME: Text::xSV::Slurp can't cope well with quotes in field contents
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
				throw Error::DB::Open(-file => "$dir/$table");
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

	$self->_open() if(!$self->{$table});

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
			throw Error::Simple("$query: argument is not a string: " . ref($arg));
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
			if($self->{'logger'}) {
				$self->{'logger'}->debug('cache HIT');
			}
			# This use of a temporary variable is to avoid
			#	"Implicit scalar context for array in return"
			# return @{$rc};
			my @rc = @{$rc};
			return @rc;
		}
		if($self->{'logger'}) {
			$self->{'logger'}->debug('cache MISS');
		}
	} elsif($self->{'logger'}) {
		$self->{'logger'}->debug('cache not used');
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
			$c->set($key, \@rc, $self->{'cache_duration'});
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
		$c->set($key, $rc, $self->{'cache_duration'});
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
	} elsif(scalar(@_) % 2 == 0) {
		%args = @_;
	} elsif((scalar(@_) == 1) && !ref($_[0])) {
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

# If the first column if the database is "entry" you can do a quick lookup with
#	my $value = $table->column($key);	# where column is the value you're after

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

	my %params;
        if(ref($_[0]) eq 'HASH') {
                %params = %{$_[0]};
        } elsif((scalar(@_) % 2) == 0) {
                %params = @_;
        } elsif(scalar(@_) == 1) {
                $params{'entry'} = shift;
        }

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
		if($self->{'data'} && ((scalar keys %params) == 1)) {
			# The data has been read in using Text::xSV::Slurp, and it's a simple query
			#	so no need to do any SQL
			my ($key, $value) = %params;
			if(my $data = $self->{'data'}) {
				foreach my $row(@{$data}) {
					if(($row->{$key} eq $value) && (my $rc = $row->{$column})) {
						if($self->{'logger'}) {
							$self->{'logger'}->trace("AUTOLOAD return '$rc' from slurped data");
						}
						return $rc;
					}
				}
			}
		}
		if(($self->{'type'} eq 'CSV') && !$self->{no_entry}) {
			$query = "SELECT DISTINCT $column FROM $table WHERE entry IS NOT NULL AND entry NOT LIKE '#%'";
			$done_where = 1;
		} else {
			$query = "SELECT DISTINCT $column FROM $table";
		}
	}
	my @args;
	while(my ($key, $value) = each %params) {
		if($self->{'logger'}) {
			$self->{'logger'}->debug(__PACKAGE__, ": AUTOLOAD adding $key=>$value");
		}
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
	if(wantarray) {
		$query .= " ORDER BY $column";
	} else {
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
