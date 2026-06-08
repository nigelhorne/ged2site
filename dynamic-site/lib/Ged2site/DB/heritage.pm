package Ged2site::DB::heritage;

# Database abstraction layer for heritage.csv
# Schema: entry!title!birth_country!dob!relationship
# Inherits all query methods from Database::Abstraction

use strict;
use warnings;
use autodie qw(:all);

use parent 'Database::Abstraction';

our $VERSION = '0.01';

1;

__END__

=encoding ASCII

=head1 NAME

Ged2site::DB::heritage - Database abstraction for heritage data

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    use Ged2site::DB::heritage;
    my $db = Ged2site::DB::heritage->new(directory => '/path/to/data');
    my @rows = $db->selectall_hash();

=head1 DESCRIPTION

Thin C<Database::Abstraction> subclass that provides access to the
C<heritage.csv> file (or its SQLite equivalent after running C<tosqlite>).

The CSV schema is: C<entry!title!birth_country!dob!relationship>.

All query, filter, and update methods are inherited from
C<Database::Abstraction>.

=head1 SEE ALSO

L<Database::Abstraction>, L<Ged2site::Display::heritage>

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 LICENCE AND COPYRIGHT

Ged2site is licensed under GPL2.0 for personal use only.

=cut
