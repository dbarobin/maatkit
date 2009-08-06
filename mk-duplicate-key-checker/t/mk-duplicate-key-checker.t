#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 12;

require '../mk-duplicate-key-checker';
require '../../common/Sandbox.pm';

my $dp = new DSNParser();
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master')
   or BAIL_OUT('Cannot connect to sandbox master');

my $cnf = '/tmp/12345/my.sandbox.cnf'; # TODO: use $sb
my $cmd = "perl ../mk-duplicate-key-checker -F $cnf";

my $output = `$cmd -d mysql -t columns_priv -v`;
like($output,
   qr/PRIMARY \(`Host`,`Db`,`User`,`Table_name`,`Column_name`\)/,
   'Finds mysql.columns_priv PK'
);

$sb->wipe_clean($dbh);
is(`$cmd -d test --nosummary`, '', 'No dupes on clean sandbox');

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', '../../common/t/samples/dupe_key.sql', 'test');

$output = `$cmd -d test | diff samples/basic_output.txt -`;
is($output, '', 'Default output');

$output = `$cmd -d test --nosql | diff samples/nosql_output.txt -`;
is($output, '', '--nosql');

$output = `$cmd -d test --nosummary | diff samples/nosummary_output.txt -`;
is($output, '', '--nosummary');

$sb->load_file('master', '../../common/t/samples/uppercase_names.sql', 'test');
$output = `$cmd -d test -t UPPER_TEST | diff samples/uppercase_names.txt -`;
is($output, '', 'Issue 306 crash on uppercase column names');

$sb->load_file('master', '../../common/t/samples/issue_269-1.sql', 'test');
$output = `$cmd -d test -t a | diff samples/issue_269.txt -`;
is($output, '', 'No dupes for issue 269');

$sb->wipe_clean($dbh);
$output = `$cmd -d test | diff samples/nonexistent_db.txt -`;
is($output, '', 'No results for nonexistent db');

# #############################################################################
# Issue 298: mk-duplicate-key-checker crashes
# #############################################################################
$output = `$cmd -d mysql -t columns_priv 2>&1`;
unlike($output, qr/Use of uninitialized var/, 'Does not crash on undef var');

# #############################################################################
# Issue 331: mk-duplicate-key-checker crashes getting size of foreign keys
# #############################################################################
$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 'samples/issue_331.sql', 'test');
$output = `$cmd -d issue_331 | diff samples/issue_331.txt -`;
is($output, '', 'Issue 331 crash on fks');

# #############################################################################
# Issue 295: Enhance rules for clustered keys in mk-duplicate-key-checker
# #############################################################################
$sb->load_file('master', 'samples/issue_295.sql', 'test');
$output = `$cmd -d issue_295 | diff samples/issue_295.txt -`;
is($output, '', "Shorten, not remove, clustered dupes");

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   mk_duplicate_key_checker::_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
exit;
