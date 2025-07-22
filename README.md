[![Tweet](https://img.shields.io/twitter/url/http/shields.io.svg?style=social)](https://x.com/intent/tweet?text=A+utility+for+creating+a+family+history+website+from+a+gedcoms+file+#genealogy&url=https://github.com/nigelhorne/ged2site&via=nigelhorne)

# ged2site

Create a Stunning Family Tree Website from Your Gedcom File!

Turn your Gedcom file into a fully interactive family tree website with Ged2Site.
This powerful tool transforms your genealogical data into a beautifully structured HTML site,
making it easy to share your family history with others.

Check out a live example of a genealogy website built with Ged2Site:
[Nigel Horne's Family Tree](https://genealogy.nigelhorne.com).

## Need Help?

Ged2Site is a feature-rich and advanced tool, and while it’s designed to be accessible, setting up a genealogy website can be complex.
If you’re a genealogist without an IT background, I’d be happy to assist you.
Reach out to me at <njh at nigelhorne.com> for professional support.

## Compatibility

It's been extensively tested with Gedcoms exported and downloaded from
FindMyPast and Family Tree Maker, though it should work fine with other systems
such as GenesReunited and Ancestry.

## Usage

Typical usage:

    ged2site -cFdh 'Your Name' gedfile.ged

You will then have two sites created in sub-directories
- static-site is static HTML (no CGI),
- dynamic-site is a [VWF](//github.com/nigelhorne/vwf) based website which uses templates to support more than one
language and present different content to mobile/web/search-engine clients.
This allows for better SEO and a seamless experience on mobile as well as desktops
in a multi-lingual environment.
This is much more easily customisable
by you to create the look and feel of the website that you want.
The dynamic site contains more data visualisation such as trend analysis,
time-lapse views and heatmaps in a visually appealing way.

## How to Use Ged2Site

To generate your family tree website, run the following command:

    ged2site -cFdh 'Your Name' gedfile.ged

This will create two website versions in separate folders:

* static-site – A simple, no-frills HTML website that works without CGI.
* dynamic-site – A more advanced website powered by [VWF](https://github.com/nigelhorne/vwf).

What’s the Difference?
* Static Site:
	* Basic HTML, easy to use, no extra setup required.
* Dynamic Site:
	* Supports multiple languages.
	* Adapts content for mobile, web, and search engines.
	* Improves SEO and user experience.
	* Easier to customize for a unique look and feel.
	* Includes data visualizations like trend analysis, time-lapse views, and heatmaps.

If you want a flexible, visually rich, and customizable family tree website, the dynamic site is the better option.

## **How to Publish Your Site**

### **For the Static Site**
If you're using the **static site**,
simply **copy all files from the `static-site` directory** to your web server.
No extra setup is needed.

### **For the Dynamic Site**
If you prefer the **dynamic site**,
follow these steps:

#### **1. Create a Configuration File**
- Go to the `conf` directory and create a new file named after your website's hostname (e.g., `yourdomain.com`).
- Use the `default` file as a template.
- Update the configuration file with key details:

  ```
  root_dir: /full/path/to/your/website
  SiteTitle: Your Website Title
  memory_cache: Stores short-term data like user locations
  disc_cache: Stores long-term data for caching and performance
  contact: Your Name and Email Address
  ```

#### **2. Customize the Site**
Modify the **template files** to change the website’s design and layout to match your needs.

#### **3. Upload to Your Web Server**
Copy the entire `dynamic-site` directory to your web server.

#### **4. Optimize Your Database (Optional)**
The dynamic site stores data in **CSV files**, but for faster performance, you can **convert them to SQLite** using [`csv2sqlite`](http://search.cpan.org/~rwstauner/App-csv2sqlite/).

Run this command on each CSV file:
```
csv2sqlite -o sep_char='!' -o allow_loose_quotes=1 people.csv people.sql
```

#### **5. Clear Old Cache**
Before uploading a new version of your site, **delete the `save_to` directory and the disc cache** to remove outdated page copies.

#### **6. Set Up Logging (Optional)**
If you want logging, edit the `page.l4pconf` file to configure it to your needs.

Once you've completed these steps, your **dynamic family tree website** will be live and optimized.

## **Installing Dependencies for Ged2Site**

### **Automatic Installation**
Ged2Site relies on multiple **CPAN modules**.
If they are missing, the program will attempt to **install them automatically** when you run it for the first time **without any arguments**
and set the evironment variable BOOTSTRAP.


```
BOOTSTRAP=1 ged2site
```

However, this **may fail** with a "permission denied" error if:
- You are **not running as root** (which is the correct and safer way).
- You are **not using** tools like [local::lib](https://metacpan.org/pod/local::lib) or [Perlbrew](https://perlbrew.pl/).

### **Manual Installation (If Automatic Installation Fails)**
If the modules do not install automatically, you have three options:

1. **Use `local::lib`** (Recommended)
   - Set up `local::lib` by following [these instructions](https://metacpan.org/pod/local::lib).
   - Install missing modules manually with CPAN:
     ```
     cpan install Module::Name
     ```

2. **Use Perlbrew**
   - Install [Perlbrew](https://perlbrew.pl/) to manage your Perl environment.
   - Install modules within your Perlbrew-managed environment.

3. **Run Ged2Site as Root** (Not Recommended)
   - You **can** run it as root, but this **is not advised** due to security risks.

### **Alternative Installation Method (Experimental)**
You can also try installing dependencies with:

```
cpan -i lazy && perl -Mlazy ged2site && perl -Mlazy dynamic-site/cgi-bin/page.cgi
```

**Note:** This method is **untested** and may not work.

### **Installing Gedcom (Required for Calendars)**
To enable calendar features on the **dynamic site**, you **must install Gedcom**:

```
git clone https://github.com/nigelhorne/gedcom.git
cd gedcom
perl Makefile.PL && make && make install
```

### **Additional Setup for FreeBSD**
If you're using **FreeBSD**, install required packages and create symbolic links:

```
sudo pkg install pkgconf gdlib graphviz ImageMagick7
cd /usr/local/lib
sudo ln -s libMagick++-7.so libMagickCore-7.Q16HDRI.so
```

### **Final Check**
Once dependencies are installed, **try running Ged2Site again**. If you still encounter issues, ensure your Perl environment is properly configured using `local::lib` or `Perlbrew`.

## Runtime Options

Ged2Site comes with various options that let you customize how your family tree website is generated.
Here’s what each option does:

### Command-Line Flags

| Flag | Description |
| ---- | ----------- |
| `-c` | Include citations in the output. |
| `-d` | Download and embed media files (e.g., images, documents) instead of linking to them. This is useful for paid sites like FindMyPast (FMP). |
| `-f` | Treat warnings as errors (stops execution if warnings occur). Implies `-w`. |
| `-F` | Generate a graphical family tree (requires GraphViz). |
| `-g` | Generate a Google verification file for search engine indexing. Enter the verification code **without** the `.html` extension. |
| `-h` | Set the home (starting) person in the tree. |
| `-l` | Include living people in the generated site. |
| `-L n` | Limit the output to **n** records. |
| `-m` | Add an interactive map to each page showing event locations. |
| `-J` | Provide a Google Maps JavaScript API key for displaying maps. The key should have an application restriction for your website. If omitted, OpenStreetMaps is used. |
| `-G` | Provide a Google Maps Geolocation API key for mapping event locations. |
| `-w` | Enable warnings for inconsistent data (like a lint tool for Gedcom files). |
| `-W` | Disable colorized warning output. |
| `-x f` | Use a previous `people.xml` file to track changes and generate a blog (TODO feature). |

### Important Notes

- If you use the `-m` option (maps), **your Google API key will be included in the website’s code**. To protect it, restrict the key’s use to your host’s IP address.
- By default, Ged2Site is designed to **protect the privacy of living individuals**.

### Additional Features

- If [Gedcom](https://github.com/nigelhorne/gedcom) is installed, Ged2Site can generate a **calendar of births and deaths**, with a dedicated page for each month of the current year.
- Ged2Site produces an **XML file (`people.xml`)** containing parsed output, which can be used in other genealogy software for queries. This means it also functions as a **Gedcom-to-XML converter**.

### Configuration File (`ged2site.conf`)

Some options can be stored in a configuration file instead of passing them every time in the command line:

| Flag | Configuration Key |
| ---- | ----------------- |
| `-h` | `home` (home person) |
| `-g` | `google_verification` (Google site verification) |
| `-G` | `google_maps_geolocation_key` (can also be set via `GMAP_GEOCODING_KEY` environment variable) |
| `-J` | `google_maps_javascript_key` |

### Getting API Keys

To use Google Maps or site verification features, get free API keys from [Google API Console](https://console.developers.google.com/apis/credentials).

## Ancestry on Windows

I use FindMyPast on Linux because the export of images is better on FMP and
because Linux.  I recognise that many folks use Ancestry on Windows, so I
have this rough guide that works for me but understand that you'll still
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
# disallow access to special directories and feedback a 404 error
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

`Ged2Site` honours the following environment variables for improved compatibility:

* BOOTSTRAP - Attempt to install the modules you need
* BMAP_KEY - Bing (virtualearth.net) API Key
* GEONAMES_USER - geonames.org registered username
* GMAP_GEOCODING_KEY - Google Places (maps.googleapis.com) API Key for encoding, locked down to the IP address you run ged2site on
* GMAP_WEBSITE_KEY - Google Places (maps.googleapis.com) API Key for displaying, locked down to your URL
* LANG - some handling of en_GB and en_US translating between then, fr_FR is a work in progress
* OPENADDR_HOME - directory of data from http -//results.openaddresses.io/
* REDIS_SERVER - ip:port pair of where to cache geo-coding data
* OPENAI_KEY - experimental: use the key from openai.com to enhance the text

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

## Premium Support

Premium support covers:

### Consulting

Expertise in setting up, customizing, and maintaining ged2site.

### Training

Paid training sessions, webinars, or workshops.

### Technical Support

Premium support plans with a guaranteed response time and direct assistance.

### Family History Website

Host your family history securely and beautifully.
By sending your Gedcom, preserving your family’s legacy online has never been easier.
Whether you're just starting your genealogy journey or managing a massive archive,
just send your Gedcom and I'll do the rest.

## **Ged2Site Licence Agreement**

### **Personal Use:**
Ged2Site is **free to use** for a **single individual** on **one computer** for **personal, non-commercial purposes only**.

### **Restricted Use:**
Any other use—including but not limited to **commercial, charitable, educational, or government organizations**—**requires a written license agreement**.

### **License Application:**
Organizations or individuals falling outside the personal-use terms **must request written permission** and obtain a license before using Ged2Site.

For licensing enquiries, please contact: **< njh @ nigelhorne.com >**.

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

If you see lumpy English text in the output or just plain mistakes,
please e-mail me or add a bug report to github.com/nigelhorne/ged2site.

Profile pictures are not handled with output from Ancestry.  Findmypast is handled correctly.

The storytelling format is hard coded, it would be useful if it were configurable.

## XML File Generation

Ged2Site generates an XML file for each individual in the database.
These files are primarily used to create dynamic content for websites.
However, in principle, they can be imported into any data viewing system that supports XML.

### File Location

The XML files are stored in the following directory:

```
.../dynamic_site/data/people/${xref}.XML
```

Each file is named based on the unique xref identifier assigned to the individual.

### Usage

The XML files enable dynamic content generation on websites.
They can be parsed and imported into other data visualization or genealogy tools,
the structured format allows easy integration with third-party systems.
For further details on the XML structure and how to use these files, refer to the XML Schema Documentation or contact the Nigel Horne.

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

* [gedcom](https://github.com/nigelhorne/gedcom) - a general-purpose utility for Gedcom files
* [gedcmp](https://github.com/nigelhorne/gedcmp) - compare two Gedcoms
* [The Perl-GEDCOM Mailing List](https://www.miskatonic.org/pg/) - dead mailing list, you can check the archives

## LICENSE AND COPYRIGHT

Copyright 2015-2025 Nigel Horne.

## Support

Please report any bugs or feature requests to the author.
This module is provided as-is without any warranty.
