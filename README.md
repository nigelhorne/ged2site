[![Tweet](https://img.shields.io/twitter/url/http/shields.io.svg?style=social)](https://x.com/intent/tweet?text=A+utility+for+creating+a+family+history+website+from+a+gedcoms+file+#genealogy&url=https://github.com/nigelhorne/ged2site&via=nigelhorne)

# ged2site

Convert a Gedcom file to HTML to create a family tree website.

An example genealogy website that was produced by ged2site is available
at https://genealogy.nigelhorne.com.

This is quite complex software, so if you are a genealogist looking to create
a website and aren't an IT guru,
it would be better to e-mail me on `<njh at nigelhorne.com>` for professional help.
The software is aimed to be useful for people with limited genealogical knowledge.
If you contact me, please let me know the program you're using to create your
Gedcom file, and the operating system you are using.

It's been tested more extensively with Gedcoms exported and downloaded from
FindMyPast and Family Tree Maker, though it should work fine with other systems
such as GenesReunited and Ancestry.

Typical usage:

    ged2site -cFdh 'Your Name' gedfile.ged

You will then have two sites created in sub directories
- static-site is static HTML (no CGI),
- dynamic-site is a [VWF](//github.com/nigelhorne/vwf) based website which uses templates to support more than one
language and present different content to mobile/web/search-engine clients.
This allows for better SEO and a seemless experience on mobile as well as desktops
in a multi-lingual environment.
This is much more easily customisable
by you to create the look and feel of the website that you want.
The dynamic site contains more data visualisation such as trend analysis,
time-lapse views and heatmaps in a visually appealing way.

If you decide to use the static site, just copy files in the static-site directory to your web-server.

If you decide to use the dynamic site first create a $hostname.com file in the
conf directory (use default as a template),
then modify the contents of the template tree so that the site looks as you
want it.
The configuration file can be in any number of formats including INI and XML.

    root_dir: /full/path/to/website directory
    SiteTitle: The title of your website
    memory_cache: where short-term volatile information is stored, such as the country of origin of the client
    disc_cache: where long-term information is stored, such as copies of output to see if HTTP 304 can be returned
    contact: your name and e-mail address

Then upload the dynamic-site directory to your web-server.
The databases are in CSV format. To speed up access you can convert to SQLite
format using
[csv2sqlite](http://search.cpan.org/~rwstauner/App-csv2sqlite/),
which you should run on each of the .csv files.

    csv2sqlite -o sep_char='!' -o allow_loose_quotes=1 people.csv people.sql

Every time you upload a new site ensure that you remove the "save_to" directory and the disc cache,
since they contain cached copies of pages that will be inconsistent with the new site.

Finally, for the dynamic site, set-up the logging, if you want any.  To do that modify the page.l4pconf file to taste.

## Installation and Pre-Requisites

Ged2site uses many CPAN modules which it will try to install if they are not
on your system.
If it doesn't have the necessary privilege to install the modules it will
fail on starting up with "permission denied" errors.
This is most likely because you're not running as root
(which is of course how it should be)
and you're not using [local::lib](https://metacpan.org/pod/local::lib),
or [Perlbrew](https://perlbrew.pl/).

Running the program for the first time with no
arguments should install them,
of course that will fail if you don't have the privilege,
in which case you'll need to add them by hand.
To install by hand you'll either have to use local::lib or perlbrew.
Of course you could also run ged2site as root,
but I strongly advise you don't do that.

You'll also need to install
[Library](https://github.com/nigelhorne/lib) - library of code common with
[gedcom](https://github.com/nigelhorne/gedcom).

On FreeBSD you'll need to
"sudo pkg install pkgconf gdlib graphviz ImageMagick7;
cd /usr/local/lib;
sudo ln -s libMagick++-7.so libMagickCore-7.Q16HDRI.so"

## Runtime Options

The options to ged2site are:

| Flag | Meaning |
| ---- | ------- |
| -c   | Give citations |
| -d   | Download copies of objects and media and include them on the generated website rather than link to them, useful if the objects are on pay sites such as FMP |
| -f   | treat warnings as fatal, implies -w |
| -F   | print a family tree (requires GraphViz) |
| -g   | Generate Google verification file - see www.google.com/webmasters/verification Don't include the .html at the end of the code |
| -h   | set the home person |
| -l   | include living people |
| -L n | Limit to n records |
| -m   | Generate a Google map on each page showing events |
| -J   | Google Maps JavaScript API key (used to display the map). Set the key's application restriction to website |
| -G   | Google Maps geolocation API key (used to populate the map) |
| -w   | print warning about inconsistent data - a sort of lint for Gedcom files, may not do as many as *[gedcom](//github.com/nigelhorne/gedcom)* |
| -W   | don't colorize warning output |
| -x f | Given a location of people.xml from a previous run, add to a blog of changes (TODO)

NOTE: when you use the -m option, your Google API key will be included in the output,
so ensure that you restrict the key's use just to this app on your host's IP.

Data privacy and handling of sensitive data is important,
the default configuration works hard to avoid sharing information about living people.

If [gedcom](https://github.com/nigelhorne/gedcom) is installed,
ged2site will also create a calendar of births and deaths,
one page for each month in the current year.

Some of the options can be stored in *ged2site.conf*:

| Flag | Meaning |
| ---- | ------- |
| -h   |  home |
| -g   |  google_verification |
| -G   |  google_maps_geolocation_key (also can be stored in the `GMAP_KEY` environment variable) |
| -J   |  google_maps_javascript_key |

You can get free API keys from Google at https://console.developers.google.com/apis/credentials.

ged2site also creates an XML file,
people.xml,
of parsed output which you can use in querying software,
so it also works as a Gedcom to XML converter.

## Ancestry on Windows

I use FindMyPast on Linux, because export of images is better on FMP and
because Linux.  I recognise that many folks use Ancestry on Windows, so I
have this rough guide which works for me, but understand that you'll still
need to be an advanced Windows user, this is not for the Novice.  If you
still need help, e-mail me or put an issue on github.com/nigelhorne/ged2site.

* Firstly, if you're running Windows 10, install
[Ubuntu](https://ubuntu.com/tutorials/ubuntu-on-windows#1-overview)
or install Perl directly, either ActiveState or Strawberry should work fine.
I have also had success using Cygwin's Perl.

* Next follow the instructions at [local::lib](https://metacpan.org/pod/local::lib#The-bootstrapping-technique).

* Load in all the CPAN modules that ged2site uses.
If you're not sure, run ged2site with no arguments and the program will install its core modules to get started.

* Install Family Tree Maker.  Sorry; there's no alternative so you'll just have
to find a copy and buy it.

* Sync your ACOM tree to FTM, ensuring you also sync all of the media.

* Create a Gedcom using File->Export, and choosing GEDCOM5.5 as the
output format.

* Run ged2site on that saved Gedcom file.

* -F may not work because it depends on Graphviz being found,
but could work under Cygwin. On the other hand, I've been hit by a Cygwin bug
when trying to call Graphviz from ged2site.  This may be because ged2site
pipes output to Graphviz, perhaps it would work if it used a temporary file
as input.

## .htaccess
I strongly suggest adding this to your .htaccess file:

```
# disallow access to special directories and feed back a 404 error
RedirectMatch 404 /\\.svn(/|$)
RedirectMatch 404 /\\.git(/|$)

<IfModule mod_expires.c>
# http://httpd.apache.org/docs/2.0/mod/mod_expires.html
ExpiresActive On

ExpiresDefault "access plus 1 hour"

ExpiresByType image/x-icon "access plus 1 month"
ExpiresByType image/png "access plus 1 month"
ExpiresByType image/jpg "access plus 1 month"
ExpiresByType image/gif "access plus 1 month"
ExpiresByType image/jpeg "access plus 1 month"

ExpiresByType text/css "access plus 1 day"
ExpiresByType text/javascript "access plus 1 day"
</IfModule>
```

## Environment Variables

For compatibility with other code, these environment variables are honoured:

    BMAP_KEY: Bing (virtualearth.net) API Key
    GEONAMES_USE: geonames.org registered username
    GMAP_KEY: Google Places (maps.googleapis.com) API Key
    LANG: some handling of en_GB and en_US translating between then, fr_FR is a work in progress
    OPENADDR_HOME: directory of data from http://results.openaddresses.io/
    REDIS_SERVER: ip:port pair of where to cache geo-coding data

## Debugging and Developing

Because the dynamic ged2site site uses VWF,
it is possible to run the scripts from the command
line simulating different environments and thus test the look and feel of your
site before you deploy. Be aware that you will also see debugging messages.

    cd dynamic-site/bin && ./tosqlite
    cd ../cgi-bin
    ./page.fcgi page=people home=1 # Look at your home entry from the -h option
    ./page.fcgi page=surnames surname=horne # List people whose surname is Horne
    ./page.fcgi page=surnames surname=horne lang=fr # List people whose surname is Horne, in French
    ./page.fcgi --mobile page=surnames surname=horne # List people whose surname is Horne, as it would appear on a smart-phone

To see the environment of the system to help with debugging

    https://localhost/cgi-bin/page.fcgi?page=meta-data

Different people use different ways to format and enter information,
ged2site goes out of its way to support all of these,
such as different location and date formats.
If your data shows issues with this aim, let me know.

## Bugs

If you see this message in your log file:
```
Can't locate auto/NetAddr/IP/InetBase/AF_INET6.al
```
this is because of a bug in the autoloader.  The fix is to edit NetAddr/IP/InetBase.pm
adding this toward the top, just after the package statement:

```
use Socket;
```

Ancestry images that you've uploaded yourself should work fine.  However, images attached
from another tree to your tree are not downloaded.  Either use
FTM or download from the other tree to your desktop and upload to your tree.

There will be numerous strange handling of Gedcoms since it's not that tightly
observed by websites.

If you see lumpy English text in the output, or just plain mistakes,
please e-mail me or add a bug report to github.com/nigelhorne/ged2site.

Profile pictures are not handled with output from Ancestry.  Findmypast is handled correctly.

The story telling format is hard coded, it would be useful if it were configurable.

## Acknowledgements

https://fullcalendar.io for the calendar view

https://github.com/weichie/animated-Timeline for the family history view

Google for the map page

Ron Savage for the HTML::Timeline module which sparked a template for the timeline code

Graphviz for the family tree and Tree::Family from CPAN for the inspiration
and code to use as a template

So many Perl CPAN modules that if I list them all I'll miss one, but special
mention goes to the Gedcom module.

Magnific Popup http://dimsemenov.com/plugins/magnific-popup/

## See Also

* [gedcom](https://github.com/nigelhorne/gedcom) - a general purpose utility for Gedcom files
* [gedcmp](https://github.com/nigelhorne/gedcmp) - compare two Gedcoms
* [lib](https://github.com/nigelhorne/lib) - library of routines used by this package
* [The Perl-GEDCOM Mailing List](https://www.miskatonic.org/pg/) - dead mailing list, you can check the archives

## LICENSE AND COPYRIGHT

Copyright 2015-2024 Nigel Horne.

This program is released under the following licence: GPL2 for personal use on
a single computer.
All other users (for example Commercial, Charity, Educational, Government)
must apply in writing for a licence for use from Nigel Horne at `<njh at nigelhorne.com>`.
