rootdir: /home/you/ged2site/dynamic-site
SiteTitle: The Family Tree of *yourname*
# memory_cache: driver=Memcached server=127.0.0.1,192.168.1.2
memory_cache: driver=File, root_dir=/tmp/cache
# disc_cache: driver=File, root_dir=/tmp/cache
disc_cache: driver=DBI, connect=dbi:SQLite:dbname=/tmp/cache/genealogy.sqlite
twitter: yourtwitterhandle
