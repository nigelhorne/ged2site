#!/usr/bin/env perl

# Regression test for https://github.com/nigelhorne/ged2site/issues/121
#
# Two bugs were reported:
#
#   Bug 1 — CONC leading-space lost:
#     GEDCOM CONC lines conventionally begin with a space to act as a word
#     separator when appended to the preceding line.  If that space is
#     stripped by the parser (or collapsed by post-processing), adjacent
#     sentences fuse: "September 30, 1923.Tragically" instead of
#     "September 30, 1923. Tragically".
#
#   Bug 2 — empty CONT swallowed:
#     An empty CONT record is the GEDCOM idiom for a paragraph break.
#     The notes() routine calls s/\n+/<\/p><p>/g when paragraph=>1, so
#     both newlines must survive full_value() for the break to appear.

use strict;
use warnings;
use Test::More tests => 5;
use File::Temp qw(tempfile);
use IPC::Run qw(run);

# Self-contained GEDCOM that exercises both failure modes.
# The second CONC line deliberately leads with a space — the only word
# boundary between "here." and "Second".  The empty CONT is the paragraph
# break signal.
my ($fh, $gedfile) = tempfile(SUFFIX => '.ged', UNLINK => 1);
print $fh <<'END';
0 HEAD
1 SOUR ged2site
1 GEDC
2 VERS 5.5
1 CHAR UTF-8
0 @I1@ INDI
1 NAME Test /Person/
1 SEX M
1 BIRT
2 DATE 1 JAN 1900
1 DEAT
2 DATE 1 JAN 1960
1 NOTE @N1@
0 @N1@ NOTE
1 CONC First sentence ends here.
1 CONC  Second sentence starts here.
1 CONT
1 CONT New paragraph text.
END
close $fh;

run ['./ged2site', '-h', 'Test Person', $gedfile],
    '>', \my $stdout, '2>', \my $stderr;

my $html_file = 'static-site/I1.html';

ok(-f $html_file, 'Person HTML file was generated');

SKIP: {
    skip 'HTML file was not generated — cannot test note rendering', 4
        unless -f $html_file;

    open(my $in, '<', $html_file) or BAIL_OUT("Cannot read $html_file: $!");
    local $/;
    my $html = <$in>;
    close $in;

    # Confirm the note content reached the HTML at all before checking detail.
    like($html, qr/First sentence/, 'Note content is present in the HTML output');

    # Bug 1: the CONC line " Second..." has a leading space that is the sole
    # separator; losing it fuses the two sentences into "here.Second".
    unlike($html, qr/here\.Second/,
        'Leading space on CONC line preserved — sentences not fused (issue #121 bug 1)');

    # The CONT paragraph text must also survive the pipeline.
    like($html, qr/New paragraph text/, 'CONT continuation text is present in output');

    # Bug 2: the empty CONT between the two blocks must produce a <p> break.
    # notes() substitutes \n+ → </p><p> when paragraph=>1, so if full_value()
    # strips the empty-CONT newline the two blocks collapse into one paragraph.
    like($html, qr{</p>.*?<p>}is,
        'Paragraph break from empty CONT line (issue #121 bug 2)');
}
