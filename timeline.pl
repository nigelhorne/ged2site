#!/usr/bin/env perl

# Author Nigel Horne: njh@bandsman.co.uk
# Copyright (C) 2017, Nigel Horne

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

# TODO: Move from CSV to XML

# -d:	Download copies of objects rather than link to them, useful if the
#	objects are on pay sites such as FMP

use strict;
use warnings;
use autodie qw(:all);
# use warnings::unused;

use HTML::Timeline;

my $ht = HTML::Timeline->new({ gedcom_file => $ARGV[0] });
$ht->run();
