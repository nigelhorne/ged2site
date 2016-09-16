<config>
	<rootdir>/home/hornenj/genealogy.nigelhorne.com</rootdir>
	<SiteTitle>The Family Tree of Nigel Horne</SiteTitle>
	<!-- Ensure timeout is disabled on the Redis server -->
	<disc_cache>
		<driver>Redis</driver>
		<server>127.0.0.1</server>
		<port>6379</port>
	</disc_cache>
	<memory_cache>
		<driver>Memcached</driver>
		<server>127.0.0.1</server>
		<port>11211</port>
	</memory_cache>
</config>
