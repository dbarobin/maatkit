#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-heartbeat/mk-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 17;
}

$sb->create_dbs($dbh, ['test']);

my $output;
my $cnf      = '/tmp/12345/my.sandbox.cnf';
my $cmd      = "$trunk/mk-heartbeat/mk-heartbeat -F $cnf ";
my $pid_file = "/tmp/__mk-heartbeat-test.pid";
my $ps_grep_cmd = "ps x | grep mk-heartbeat | grep daemonize | grep -v grep";

$dbh->do('drop table if exists test.heartbeat');
$dbh->do(q{CREATE TABLE test.heartbeat (
             id int NOT NULL PRIMARY KEY,
             ts datetime NOT NULL
          ) ENGINE=MEMORY});

# Issue: mk-heartbeat should check that the heartbeat table has a row
$output = `$cmd -D test --check --no-insert-heartbeat-row 2>&1`;
like($output, qr/heartbeat table is empty/ms, 'Dies on empty heartbeat table with --check (issue 45)');

$output = `$cmd -D test --monitor --run-time 1s --no-insert-heartbeat-row 2>&1`;
like($output, qr/heartbeat table is empty/ms, 'Dies on empty heartbeat table with --monitor (issue 45)');

$output = output(
   sub { mk_heartbeat::main('-F', $cnf, qw(-D test --check)) },
);
my $row = $dbh->selectall_hashref('select * from test.heartbeat', 'id');
is(
   $row->{1}->{id},
   1,
   "Automatically inserts heartbeat row (issue 1292)"
);

# Run one instance with --replace to create the table.
`$cmd -D test --update --replace --run-time 1s`;
ok($dbh->selectrow_array('select id from test.heartbeat'), 'Record is there');

# Check the delay and ensure it is only a single line with nothing but the
# delay (no leading whitespace or anything).
$output = `$cmd -D test --check`;
chomp $output;
like($output, qr/^\d+$/, 'Output is just a number');

# Start one daemonized instance to update it
system("$cmd --daemonize -D test --update --run-time 3s --pid $pid_file 1>/dev/null 2>/dev/null");
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');

ok(-f $pid_file, 'PID file created');
my ($pid) = $output =~ /^\s*(\d+)\s+/;
$output = `cat $pid_file`;
is($output, $pid, 'PID file has correct PID');

$output = `$cmd -D test --monitor --run-time 1s`;
chomp ($output);
is (
   $output,
   '   0s [  0.00s,  0.00s,  0.00s ]',
   'It is being updated',
);
sleep(3);
$output = `$ps_grep_cmd`;
chomp $output;
unlike($output, qr/$cmd/, 'It is not running anymore');
ok(! -f $pid_file, 'PID file removed');

# Run again, create the sentinel, and check that the sentinel makes the
# daemon quit.
system("$cmd --daemonize -D test --update 1>/dev/null 2>/dev/null");
$output = `$ps_grep_cmd`;
like($output, qr/$cmd/, 'It is running');
$output = `$cmd -D test --stop`;
like($output, qr/Successfully created/, 'Created sentinel');
sleep(2);
$output = `$ps_grep_cmd`;
unlike($output, qr/$cmd/, 'It is not running');
ok(-f '/tmp/mk-heartbeat-sentinel', 'Sentinel file is there');
unlink('/tmp/mk-heartbeat-sentinel');
$dbh->do('drop table if exists test.heartbeat'); # This will kill it

# #############################################################################
# Issue 353: Add --create-table to mk-heartbeat
# #############################################################################

# These creates the new table format, whereas the preceding tests used the
# old format, so tests from here on may need --master-server-id.

$dbh->do('drop table if exists test.heartbeat');
diag(`$cmd --update --run-time 1s --database test --table heartbeat --create-table`);
$dbh->do('use test');
$output = $dbh->selectcol_arrayref('SHOW TABLES LIKE "heartbeat"');
is(
   $output->[0],
   'heartbeat', 
   '--create-table creates heartbeat table'
); 

# #############################################################################
# Issue 352: Add port to mk-heartbeat --check output
# #############################################################################
sleep 1;
$output = `$cmd --host 127.1 --user msandbox --password msandbox --port 12345 -D test --check --recurse 1 --master-server-id 12345`;
like(
   $output,
   qr/:12346\s+\d/,
   '--check output has :port'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
