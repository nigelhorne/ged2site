gedsite
=======

Converts a Gedcom file to HTML to create family tree website.

It's been tested more extensively with GedComs exported and downloaded from
FindMyPast, though it should work fine with other systems such as GenesReunited
and Ancestry.

Typical usage:

    gedsite -cFdh 'Your Name' gedfile.ged
    copy files in the html directory to your webserver

The options are:

    -c: Give citations
    -d: Download copies of objects and media and include them on the generated
	website rather than link to them, useful if the objects are on pay
	sites such as FMP
    -f: treat warnings as fatals, implies -w
    -F: print a family tree (requires GraphViz)
    -g: Generate Google verification file - see www.google.com/webmasters/verification
	Don't include the .html at the end of the code
    -h: set the home person
    -l: include living people
    -w: print warning about inconsistent data - a sort of lint for Gedcom files,
	may not do as many as gedcal(1)

If gedcal is installed, gedsite will also create a calendar of births and
deaths, one page for each month in the current year.
