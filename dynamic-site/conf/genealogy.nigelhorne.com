<config>
	<rootdir>/home/hornenj/genealogy.nigelhorne.com</rootdir>
	<SiteTitle>The Family Tree of Nigel Horne</SiteTitle>
	<twitter>nigelhorne</twitter>
	<disc_cache>
		<driver>DBI</driver>
		<connect>dbi:SQLite:dbname=/tmp/genealogy.sqlite</connect>
	</disc_cache>
	<memory_cache>
		<driver>Memcached</driver>
		<server>127.0.0.1</server>
		<port>11211</port>
	</memory_cache>
	<contact>
		<name>Nigel Horne</name>
		<email>njh@bandsman.co.uk</email>
	</contact>
</config>
