package Ged2site::DB::military;

# The database associated with the military template file:
#	military.csv, one row per military record, entry!person!date!place!notes

use strict;
use warnings;
use autodie qw(:all);

use parent 'Database::Abstraction';

our $VERSION = '0.02';

1;
