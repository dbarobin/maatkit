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
require "$trunk/mk-table-sync/mk-table-sync";

my $output;
my $vp = new VersionParser();
my $dp = new DSNParser(opts=>$dsn_opts);
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
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);

# #############################################################################
# Issue 376: Permit specifying an index for mk-table-sync
# #############################################################################
diag(`/tmp/12345/use < $trunk/mk-table-sync/t/samples/issue_375.sql`);
sleep 1;
$output = `$trunk/mk-table-sync/mk-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-index updated_at`;
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 02:38:12'/,
   '--chunk-index',
);

$output = `$trunk/mk-table-sync/mk-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-column updated_at`;
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 02:38:12'/,
   '--chunk-column',
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
