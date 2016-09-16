ged2site
========

Converts a Gedcom file to HTML to create family tree website.

It's been tested more extensively with GedComs exported and downloaded from
FindMyPast, though it should work fine with other systems such as GenesReunited
and Ancestry.

Typical usage:

    ged2site -cFdh 'Your Name' gedfile.ged

You will then have two sites - static-site is static HTML,
dynamic-site is a VWF based website which uses templates to support more than one
language and mobile/web/search-engine clients.

If you decide to use the static site, just copy files in the static-site directory to your webserver.
If you decide to use the dynamic site first create a $hostname.com file in the conf directory (use
example.com as a template), then modify the contents of the template tree so that the site looks as
you want it.  Then upload the dynamic-site directory to your webserver.

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
    -m: Generate a Google map on each page showing events
    -M: Google maps API key
    -w: print warning about inconsistent data - a sort of lint for Gedcom files,
	may not do as many as gedcal(1)

If gedcal is installed, ged2site will also create a calendar of births and
deaths, one page for each month in the current year.

An example dynamic genealogy website that was produced by Ged2site is available
at https://genealogy.nigelhorne.com.

Note that the dynamic page generation is in its early stages of development so
not all of the data is available yet.

Acknowledgements:

http://fullcalendar.io for the calendar view

https://github.com/weichie/animated-Timeline for the family history view

Google for the map page

Graphviz for the family tree and Tree::Family from CPAN for the inspiration
	and code to use as a template

So many CPAN modules that if I list them all I'll miss one, but special mention
	goes to the Gedcom module.
