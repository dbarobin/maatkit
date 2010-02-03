#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
   unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

# Open a connection to MySQL, or skip the rest of the tests.
use DSNParser;
use Sandbox;
use MaatkitTest;

my $dp  = new DSNParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( $dbh ) {
   plan tests => 33;
}
else {
   plan skip_all => 'Cannot connect to MySQL';
}

$sb->create_dbs($dbh, ['test']);

use TableSyncChunk;
use Quoter;
use ChangeHandler;
use TableChecksum;
use TableChunker;
use TableParser;
use MySQLDump;
use VersionParser;
use TableSyncer;
use MasterSlave;

my $mysql = $sb->_use_for('master');

diag(`$mysql < $trunk/common/t/samples/before-TableSyncChunk.sql`);

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $du = new MySQLDump();
my $vp = new VersionParser();
my $ms = new MasterSlave();
my $chunker    = new TableChunker( Quoter => $q, MySQLDump => $du );
my $checksum   = new TableChecksum( Quoter => $q, VersionParser => $vp );
my $syncer     = new TableSyncer(
   MasterSlave   => $ms,
   TableChecksum => $checksum,
   Quoter        => $q,
   VersionParser => $vp
);

my $ddl;
my $tbl_struct;
my %args;
my @rows;
my $src = {
   db  => 'test',
   tbl => 'test1',
   dbh => $dbh,
};
my $dst = {
   db  => 'test',
   tbl => 'test1',
   dbh => $dbh,
};

my $ch = new ChangeHandler(
   Quoter    => new Quoter(),
   right_db  => 'test',
   right_tbl => 'test1',
   left_db   => 'test',
   left_tbl  => 'test1',
   replace   => 0,
   actions   => [ sub { push @rows, $_[0] }, ],
   queue     => 0,
);

my $t = new TableSyncChunk(
   TableChunker  => $chunker,
   Quoter        => $q,
);
isa_ok($t, 'TableSyncChunk');

$ddl        = $du->get_create_table($dbh, $q, 'test', 'test1');
$tbl_struct = $tp->parse($ddl);
%args       = (
   src           => $src,
   dst           => $dst,
   dbh           => $dbh,
   db            => 'test',
   tbl           => 'test1',
   tbl_struct    => $tbl_struct,
   cols          => $tbl_struct->{cols},
   chunk_col     => 'a',
   chunk_index   => 'PRIMARY',
   chunk_size    => 2,
   where         => 'a>2',
   crc_col       => '__crc',
   index_hint    => 'USE INDEX (`PRIMARY`)',
   ChangeHandler => $ch,
);
$t->prepare_to_sync(%args);

# Test with FNV_64 just to make sure there are no errors
eval { $dbh->do('select fnv_64(1)') };
SKIP: {
   skip 'No FNV_64 function installed', 1 if $EVAL_ERROR;

   $t->set_checksum_queries(
      $syncer->make_checksum_queries(%args, function => 'FNV_64')
   );
   is(
      $t->get_sql(
         where      => 'foo=1',
         database   => 'test',
         table      => 'test1', 
      ),
      q{SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, }
      . q{LOWER(CONV(BIT_XOR(CAST(FNV_64(`a`, `b`) AS UNSIGNED)), 10, 16)) AS }
      . q{crc FROM `test`.`test1` USE INDEX (`PRIMARY`) WHERE (1=1) AND ((foo=1))},
      'First nibble SQL with FNV_64 (with USE INDEX)',
   );
}

$t->set_checksum_queries(
   $syncer->make_checksum_queries(%args, function => 'SHA1')
);
is_deeply(
   $t->{chunks},
   [
      # it should really chunk in chunks of 1, but table stats are bad.
      '1=1',
   ],
   'Chunks with WHERE'
);

unlike(
   $t->get_sql(
      where    => 'foo=1',
      database => 'test',
      table    => 'test1',
   ),
   qr/SQL_BUFFER_RESULT/,
   'No buffering',
);

# SQL_BUFFER_RESULT only appears in the row query, state 1 or 2.
$t->prepare_to_sync(%args, buffer_in_mysql => 1);
$t->{state} = 1;
like(
   $t->get_sql(
      where    => 'foo=1',
      database => 'test',
      table    => 'test1', 
   ),
   qr/SELECT ..rows in chunk.. SQL_BUFFER_RESULT/,
   'Has SQL_BUFFER_RESULT',
);

# Remove the WHERE so we get enough rows to make chunks.
$args{where} = undef;
$t->prepare_to_sync(%args);
$t->set_checksum_queries(
   $syncer->make_checksum_queries(%args, function => 'SHA1')
);
is_deeply(
   $t->{chunks},
   [
      '`a` < 3',
      '`a` >= 3',
   ],
   'Chunks'
);

like(
   $t->get_sql(
      where    => 'foo=1',
      database => 'test',
      table    => 'test1',
   ),
   qr/SELECT .*?CONCAT_WS.*?`a` < 3/,
   'First chunk SQL (without index hint)',
);

is_deeply($t->key_cols(), [qw(chunk_num)], 'Key cols in state 0');
$t->done_with_rows();

like($t->get_sql(
      quoter     => $q,
      where      => 'foo=1',
      database   => 'test',
      table      => 'test1',
      index_hint => 'USE INDEX (`PRIMARY`)',
   ),
   qr/SELECT .*?CONCAT_WS.*?FROM `test`\.`test1` USE INDEX \(`PRIMARY`\) WHERE.*?`a` >= 3/,
   'Second chunk SQL (with index hint)',
);

$t->done_with_rows();
ok($t->done(), 'Now done');

# Now start over, and this time "find some bad chunks," as it were.

$t->prepare_to_sync(%args);
$t->set_checksum_queries(
   $syncer->make_checksum_queries(%args, function => 'SHA1')
);
throws_ok(
   sub { $t->not_in_left() },
   qr/in state 0/,
   'not_in_(side) illegal in state 0',
);

# "find a bad row"
$t->same_row(
   lr => { chunk_num => 0, cnt => 0, crc => 'abc' },
   rr => { chunk_num => 0, cnt => 1, crc => 'abc' },
);
ok($t->pending_changes(), 'Pending changes found');
is($t->{state}, 1, 'Working inside chunk');
$t->done_with_rows();
is($t->{state}, 2, 'Now in state to fetch individual rows');
ok($t->pending_changes(), 'Pending changes not done yet');
is(
   $t->get_sql(
      database => 'test',
      table    => 'test1',
   ),
   "SELECT /*rows in chunk*/ `a`, SHA1(CONCAT_WS('#', `a`, `b`)) AS __crc FROM "
      . "`test`.`test1` USE INDEX (`PRIMARY`) WHERE (`a` < 3)"
      . " ORDER BY `a`",
   'SQL now working inside chunk'
);
ok($t->{state}, 'Still working inside chunk');
is(scalar(@rows), 0, 'No bad row triggered');

$t->not_in_left(rr => {a => 1});

is_deeply(\@rows,
   ['DELETE FROM `test`.`test1` WHERE `a`=1 LIMIT 1'],
   'Working inside chunk, got a bad row',
);

# Should cause it to fetch back from the DB to figure out the right thing to do
$t->not_in_right(lr => {a => 1});
is_deeply(\@rows,
   [
   'DELETE FROM `test`.`test1` WHERE `a`=1 LIMIT 1',
   "INSERT INTO `test`.`test1`(`a`, `b`) VALUES (1, 'en')",
   ],
   'Missing row fetched back from DB',
);

# Shouldn't cause anything to happen
$t->same_row( lr => {a => 1, __crc => 'foo'}, rr => {a => 1, __crc => 'foo'} );

is_deeply(\@rows,
   [
   'DELETE FROM `test`.`test1` WHERE `a`=1 LIMIT 1',
   "INSERT INTO `test`.`test1`(`a`, `b`) VALUES (1, 'en')",
   ],
   'No more rows added',
);

$t->same_row( lr => {a => 1, __crc => 'foo'}, rr => {a => 1, __crc => 'bar'} );

is_deeply(\@rows,
   [
      'DELETE FROM `test`.`test1` WHERE `a`=1 LIMIT 1',
      "INSERT INTO `test`.`test1`(`a`, `b`) VALUES (1, 'en')",
      "UPDATE `test`.`test1` SET `b`='en' WHERE `a`=1 LIMIT 1",
   ],
   'Row added to update differing row',
);

$t->done_with_rows();
is($t->{state}, 0, 'Now not working inside chunk');
is($t->pending_changes(), 0, 'No pending changes');

# ###########################################################################
# Test can_sync().
# ###########################################################################
$ddl        = $du->get_create_table($dbh, $q, 'test', 'test6');
$tbl_struct = $tp->parse($ddl);
is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct) ],
   [],
   'Cannot sync table1 (no good single column index)'
);

$ddl        = $du->get_create_table($dbh, $q, 'test', 'test5');
$tbl_struct = $tp->parse($ddl);
is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct) ],
   [],
   'Cannot sync table5 (no indexes)'
);

# create table test3(a int not null primary key, b int not null, unique(b));

$ddl        = $du->get_create_table($dbh, $q, 'test', 'test3');
$tbl_struct = $tp->parse($ddl);
is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct) ],
   [ 1,
     chunk_col   => 'a',
     chunk_index => 'PRIMARY',
   ],
   'Can sync table3, chooses best col and index'
);

is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct, chunk_col=>'b') ],
   [ 1,
     chunk_col   => 'b',
     chunk_index => 'b',
   ],
   'Can sync table3 with requested col'
);

is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct, chunk_index=>'b') ],
   [ 1,
     chunk_col   => 'b',
     chunk_index => 'b',
   ],
   'Can sync table3 with requested index'
);
 
is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct, chunk_col=>'b', chunk_index=>'b') ],
   [ 1,
     chunk_col   => 'b',
     chunk_index => 'b',
   ],
   'Can sync table3 with requested col and index'
);

is_deeply(
   [ $t->can_sync(tbl_struct=>$tbl_struct, chunk_col=>'b', chunk_index=>'PRIMARY') ],
   [],
   'Cannot sync table3 with requested col and index'
);


# #############################################################################
# Issue 560: mk-table-sync generates impossible WHERE
# #############################################################################
$t->prepare_to_sync(%args, index_hint => undef, replicate => 'test.checksum');
is(
   $t->get_sql(
      where    => 'x > 1 AND x <= 9',
      database => 'test',
      table    => 'test1', 
   ),
   "SELECT /*test.test1:1/1*/ 0 AS chunk_num, COUNT(*) AS cnt, LOWER(CONCAT(LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 1, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc, 17, 16), 16, 10) AS UNSIGNED)), 10, 16), 16, '0'), LPAD(CONV(BIT_XOR(CAST(CONV(SUBSTRING(\@crc := SHA1(CONCAT_WS('#', `a`, `b`)), 33, 8), 16, 10) AS UNSIGNED)), 10, 16), 8, '0'))) AS crc FROM `test`.`test1`  WHERE (1=1) AND ((x > 1 AND x <= 9))",
   'Use only --replicate chunk boundary (chunk sql)'
);

$t->{state} = 2;
is(
   $t->get_sql(
      where    => 'x > 1 AND x <= 9',
      database => 'test',
      table    => 'test1', 
   ),
   "SELECT /*rows in chunk*/ `a`, SHA1(CONCAT_WS('#', `a`, `b`)) AS __crc FROM `test`.`test1`  WHERE (1=1) AND (x > 1 AND x <= 9) ORDER BY `a`",
   'Use only --replicate chunk boundary (row sql)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
