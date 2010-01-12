#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
   unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-table-checksum/mk-table-checksum";

my $dp = new DSNParser();
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 31;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/mk-table-checksum/mk-table-checksum -F $cnf 127.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 'mk-table-checksum/t/samples/before.sql');

# Check --schema
$output = `$cmd --tables checksum_test --checksum --schema 2>&1`;
like($output, qr/2752458186\s+127.1.test2.checksum_test/, 'Checksum test with --schema' );

# Should output the same thing, it only lacks the AUTO_INCREMENT specifier.
like($output, qr/2752458186\s+127.1.test.checksum_test/, 'Checksum 2 test with --schema' );

# #############################################################################
# Issue 5: Add ability to checksum table schema instead of data
# #############################################################################

# The following --schema tests are sensitive to what schemas exist on the
# sandbox server. The sample file is for a blank server, i.e. just the mysql
# db and maybe or not the sakila db.
$sb->wipe_clean($master_dbh);

my $awk_slice = "awk '{print \$1,\$2,\$7}'";

my $ret_val = system("$cmd P=12346 --ignore-databases sakila --schema | $awk_slice | diff $trunk/mk-table-checksum/t/samples/sample_schema_opt -");
cmp_ok($ret_val, '==', 0, '--schema basic output');

$output = `$cmd --schema --quiet`;
is(
   $output,
   '',
   '--schema respects --quiet'
);

$output = `$cmd --schema --ignore-databases mysql,sakila`;
is(
   $output,
   '',
   '--schema respects --ignore-databases'
);

$output = `$cmd --schema --ignore-tables users`;
unlike(
   $output,
   qr/users/,
   '--schema respects --ignore-tables'
);

# Remember to add $#opt_combos+1 number of tests to line 30.
my @opt_combos = ( # --schema and
   '--algorithm=BIT_XOR',
   '--algorithm=ACCUM',
   '--chunk-size=1M',
   '--count',
   '--crc',
   '--empty-replicate-table',
   '--float-precision=3',
   '--function=FNV_64',
   '--lock',
   '--optimize-xor',
   '--probability=1',
   '--replicate-check=1000',
   '--replicate=checksum_tbl',
   '--resume samples/resume01_partial.txt',
   '--since \'"2008-01-01" - interval 1 day\'',
   '--slave-lag',
   '--sleep=1000',
   '--wait=1000',
   '--where="id > 1000"',
);

foreach my $opt_combo ( @opt_combos ) {
   $output = `$cmd P=12346 --ignore-databases sakila --schema $opt_combo 2>&1`;
   my ($other_opt) = $opt_combo =~ m/^([\w-]+\b)/;
   like(
      $output,
      qr/--schema is not allowed with $other_opt/,
      "--schema is not allowed with $other_opt"
   );
}
# Have to do this one manually be --no-verify is --verify in the
# error output which confuses the regex magic for $other_opt.
$output = `$cmd P=12346 --ignore-databases sakila --schema --no-verify 2>&1`;
like(
   $output,
   qr/--schema is not allowed with --verify/,
   "--schema is not allowed with --[no]verify"
);

# Check that --schema does NOT lock by default
$output = `MKDEBUG=1 $cmd P=12346 --schema 2>&1`;
unlike($output, qr/LOCK TABLES /, '--schema does not lock tables by default');

$output = `MKDEBUG=1 $cmd P=12346 --schema --lock 2>&1`;
unlike($output, qr/LOCK TABLES /, '--schema does not lock tables even with --lock');

# #############################################################################
# Test issue 5 + 35: --schema a missing table
# #############################################################################
$sb->create_dbs($master_dbh, [qw(test)]);
diag(`/tmp/12345/use -e 'SET SQL_LOG_BIN=0; CREATE TABLE test.only_on_master(a int);'`);

$output = `$cmd P=12346 -t test.only_on_master --schema 2>&1`;
like($output, qr/MyISAM\s+NULL\s+23678842/, 'Table on master checksummed with --schema');
like($output, qr/MyISAM\s+NULL\s+NULL/, 'Missing table on slave checksummed with --schema');
like($output, qr/test.only_on_master does not exist on slave 127\.1:12346/, 'Debug reports missing slave table with --schema');

diag(`/tmp/12345/use -e 'DROP TABLE IF EXISTS test.only_on_master'`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
