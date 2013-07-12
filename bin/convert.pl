use strict;
use warnings;

use YAML qw(DumpFile LoadFile);
use DBIx::RunSQL;
use DBI;

die 'has pm.db' if -e 'pm.db';


my $dsn = "dbi:SQLite:dbname=pm.db";
DBIx::RunSQL->create(
	verbose => 0,
	dsn     => $dsn,
	sql     => 'sql/schema1.sql',
);

my $dbh = DBI->connect($dsn, "", "", {
	RaiseError => 1,
	PrintError => 0,
	AutoCommit => 1,
});

