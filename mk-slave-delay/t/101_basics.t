#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More ;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-slave-delay/mk-slave-delay";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 5;
}

my $output;
my $cnf = '/tmp/12346/my.sandbox.cnf';
my $cmd = "$trunk/mk-slave-delay/mk-slave-delay -F $cnf h=127.1";

$output = `$cmd --help`;
like($output, qr/Prompt for a password/, 'It compiles');

# #############################################################################
# Issue 149: h is required even with S, for slavehost argument
# #############################################################################
$output = `$trunk/mk-slave-delay/mk-slave-delay --run-time 1s --delay 1s --interval 1s S=/tmp/12346/mysql_sandbox12346.sock 2>&1`;
unlike($output, qr/Missing DSN part 'h'/, 'Does not require h DSN part');

# #############################################################################
# Issue 215.  Specify SLAVE-HOST and MASTER-HOST, but MASTER-HOST does not have
# binary logging turned on, so SHOW MASTER STATUS is empty.  (This happens quite
# easily when you connect to a SLAVE-HOST twice by accident.)  To reproduce,
# just disable log-bin and log-slave-updates on the slave.
# #####1#######################################################################
diag(`cp /tmp/12346/my.sandbox.cnf /tmp/12346/my.sandbox.cnf-original`);
diag(`sed -i '/log.bin\\|log.slave/d' /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$output = `$trunk/mk-slave-delay/mk-slave-delay --delay 1s h=127.1,P=12346,u=msandbox,p=msandbox h=127.1 2>&1`;
like(
   $output,
   qr/Binary logging is disabled/,
   'Detects master that is not a master'
);

diag(`/tmp/12346/stop >/dev/null`);
diag(`mv /tmp/12346/my.sandbox.cnf-original /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);
diag(`/tmp/12346/use -e "set global read_only=1"`);

# #############################################################################
# Check --use-master
# #############################################################################
$output = `$trunk/mk-slave-delay/mk-slave-delay --run-time 1s --interval 1s --use-master --host 127.1 --port 12346 -u msandbox -p msandbox`;
sleep 1;
like(
   $output,
   qr/slave running /,
   '--use-master'
);

$output = `$trunk/mk-slave-delay/mk-slave-delay --run-time 1s --interval 1s --use-master --host 127.1 --port 12345 -u msandbox -p msandbox 2>&1`;
like(
   $output,
   qr/No SLAVE STATUS found/,
   'No SLAVE STATUS on master'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
