#!/usr/bin/env perl

# Author Nigel Horne: njh@bandsman.co.uk
# Copyright (C) 2017, Nigel Horne

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

use strict;
use warnings;
use autodie qw(:all);
# use warnings::unused;

use HTML::Timeline;

HTML::Timeline->new(options => { gedcom_file => $ARGV[0] })->run();
