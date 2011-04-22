#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 21;

use MaatkitTest;
use QueryParser;
use SQLParser;
use TableUsage;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $qp = new QueryParser();
my $sp = new SQLParser();
my $ta = new TableUsage(QueryParser => $qp, SQLParser => $sp);
isa_ok($ta, 'TableUsage');

sub test_get_table_usage {
   my ( $query, $cats, $desc ) = @_;
   my $got = $ta->get_table_usage(query=>$query);
   is_deeply(
      $got,
      $cats,
      $desc,
   ) or print Dumper($got);
   return;
}

# ############################################################################
# Queries parsable by SQLParser: SELECT, INSERT, UPDATE and DELETE
# ############################################################################
test_get_table_usage(
   "SELECT * FROM d.t WHERE id>100",
   [
      [
         { context => 'SELECT',
           table   => 'd.t',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "SELECT FROM one table"
); 

test_get_table_usage(
   "SELECT t1.* FROM d.t1 LEFT JOIN d.t2 USING (id) WHERE d.t2.foo IS NULL",
   [
      [
         { context => 'SELECT',
           table   => 'd.t1',
         },
         { context => 'JOIN',
           table   => 'd.t1',
         },
         { context => 'JOIN',
           table   => 'd.t2',
         },
         { context => 'WHERE',
           table   => 'd.t2',
         },
      ],
   ],
   "SELECT JOIN two tables"
); 

test_get_table_usage(
   "DELETE FROM d.t WHERE type != 'D' OR type IS NULL",
   [
      [
         { context => 'DELETE',
           table   => 'd.t',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "DELETE one table"
); 

test_get_table_usage(
   "INSERT INTO d.t (col1, col2) VALUES ('a', 'b')",
   [
      [
         { context => 'INSERT',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "INSERT VALUES, no SELECT"
); 

test_get_table_usage(
   "INSERT INTO d.t SET col1='a', col2='b'",
   [
      [
         { context => 'INSERT',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "INSERT SET, no SELECT"
); 

test_get_table_usage(
   "UPDATE d.t SET foo='bar' WHERE foo IS NULL",
   [
      [
         { context => 'UPDATE',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "UPDATE one table"
); 

test_get_table_usage(
   "SELECT * FROM zn.edp
      INNER JOIN zn.edp_input_key edpik     ON edp.id = edpik.id
      INNER JOIN `zn`.`key`       input_key ON edpik.input_key = input_key.id
      WHERE edp.id = 296",
   [
      [
         { context => 'SELECT',
           table   => 'zn.edp',
         },
         { context => 'SELECT',
           table   => 'zn.edp_input_key',
         },
         { context => 'SELECT',
           table   => 'zn.key',
         },
         { context => 'JOIN',
           table   => 'zn.edp',
         },
         { context => 'JOIN',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.key',
         },
         { context => 'WHERE',
           table   => 'zn.edp',
         },
      ],
   ],
   "SELECT with 2 JOIN and WHERE"
);

test_get_table_usage(
   "REPLACE INTO db.tblA (dt, ncpc)
      SELECT dates.dt, scraped.total_r
        FROM tblB          AS dates
        LEFT JOIN dbF.tblC AS scraped
          ON dates.dt = scraped.dt AND dates.version = scraped.version",
   [
      [
         { context => 'REPLACE',
           table   => 'db.tblA',
         },
         { context => 'SELECT',
           table   => 'tblB',
         },
         { context => 'SELECT',
           table   => 'dbF.tblC',
         },
         { context => 'JOIN',
           table   => 'tblB',
         },
         { context => 'JOIN',
           table   => 'dbF.tblC',
         },
      ],
   ],
   "REPLACE SELECT JOIN"
);

test_get_table_usage(
   'UPDATE t1 AS a JOIN t2 AS b USING (id) SET a.foo="bar" WHERE b.foo IS NOT NULL',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 1, filters by 1"
);

test_get_table_usage(
   'UPDATE t1 INNER JOIN t2 USING (id) SET t1.foo="bar" WHERE t1.id>100 AND t2.id>200',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 1, filters by 2"
);

test_get_table_usage(
   'UPDATE t1 AS a JOIN t2 AS b USING (id) SET a.foo="bar", b.foo="bat" WHERE a.id=1',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
      ],
      [
         { context => 'UPDATE',
           table   => 't2',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 2, filters by 1"
);

test_get_table_usage(
   'insert into t1 (a, b, c) select x, y, z from t2 where x is not null',
   [
      [
         { context => 'INSERT',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "INSERT INTO t1 SELECT FROM t2",
);

test_get_table_usage(
   'insert into t (a, b, c) select a.x, a.y, b.z from a, b where a.id=b.id',
   [
      [
         { context => 'INSERT',
           table   => 't',
         },
         { context => 'SELECT',
           table   => 'a',
         },
         { context => 'SELECT',
           table   => 'b',
         },
         { context => 'JOIN',
           table   => 'a',
         },
         { context => 'JOIN',
            table  => 'b',
         },
      ],
   ],
   "INSERT INTO t SELECT FROM a, b"
);

test_get_table_usage(
   'INSERT INTO bar
      SELECT edpik.* 
         FROM zn.edp 
            INNER JOIN zn.edp_input_key AS edpik ON edpik.id = edp.id 
            INNER JOIN `zn`.`key` input_key 
            INNER JOIN foo
         WHERE edp.id = 296
            AND edpik.input_key = input_key.id',
   [
      [
         { context => 'INSERT',
           table   => 'bar',
         },
         { context => 'SELECT',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.edp',
         },
         { context => 'JOIN',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.key',
         },
         { context => 'TLIST',
           table   => 'foo',
         },
         { context => 'WHERE',
           table   => 'zn.edp',
         },

      ],
   ],
   "INSERT SELECT with TLIST table"
);

test_get_table_usage(
   "select country.country, city.city from city join country using (country_id) where country = 'Brazil' and city like 'A%' limit 1",
   [
      [
         { context => 'SELECT',
           table   => 'country',
         },
         { context => 'SELECT',
           table   => 'city',
         },
         { context => 'JOIN',
           table   => 'city',
         },
         { context => 'JOIN',
           table   => 'country',
         },
      ],
   ],
   "Unresolvable tables in WHERE"
);

test_get_table_usage(
   "select c from t where 1",
   [
      [
         { context => 'SELECT',
           table   => 't',
         },
         { context => 'WHERE',
           table   => 'DUAL',
         },
      ],
   ],
   "WHERE <constant>"
);

test_get_table_usage(
   "select c from t where 1=1",
   [
      [
         { context => 'SELECT',
           table   => 't',
         },
         { context => 'WHERE',
           table   => 'DUAL',
         },
      ],
   ],
   "WHERE <constant>=<constant>"
);

test_get_table_usage(
   "select now()",
   [
      [
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "SELECT NOW()"
);

# ############################################################################
# Queries parsable by QueryParser
# ############################################################################
test_get_table_usage(
   "ALTER TABLE tt.ks ADD PRIMARY KEY(`d`,`v`)",
   [
      [
         { context => 'ALTER',
         table   => 'tt.ks',
         },
      ],
   ],
   "ALTER TABLE"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $ta->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;