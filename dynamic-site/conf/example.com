rootdir: /home/you/ged2site/dynamic-site
SiteTitle: The Family Tree of Nigel Horne
Files: a=b
Files: c=d
# cache: driver=BerkeleyDB root_dir=/tmp/cache
# cache: driver=Memcached server=127.0.0.1,192.168.1.2
# disc_cache: driver=File, root_dir=/tmp/cache
disc_cache: driver=DBI, connect=dbi:SQLite:dbname=/tmp/cache/genealogy.sqlite
memory_cache: driver=File, root_dir=/tmp/cache
