#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require "../ErrorLogParser.pm";

my $p = new ErrorLogParser();

my $oktorun = 1;

sub run_test {
   my ( $def ) = @_;
   map     { die "What is $_ for?" }
      grep { $_ !~ m/^(?:misc|file|result|num_events|oktorun)$/ }
      keys %$def;
   my @e;
   eval {
      open my $fh, "<", $def->{file} or die $OS_ERROR;
      my %args = (
         fh      => $fh,
         misc    => $def->{misc},
         oktorun => $def->{oktorun},
      );
      while ( my $e = $p->parse_event(%args) ) {
         push @e, $e;
      }
      close $fh;
   };
   is($EVAL_ERROR, '', "No error on $def->{file}");
   if ( defined $def->{result} ) {
      is_deeply(\@e, $def->{result}, $def->{file})
         or print "Got: ", Dumper(\@e);
   }
   if ( defined $def->{num_events} ) {
      is(scalar @e, $def->{num_events}, "$def->{file} num_events");
   }
}

run_test({
   file    => 'samples/errlog001.txt',
   oktorun => sub { $oktorun = $_[0]; },
   result => [
      {
       arg        => 'mysqld started',
       pos_in_log => 0,
       ts         => '080721 03:03:57',
      },
      {
       Serious    => 'No',
       arg        => '[Warning] option \'log_slow_rate_limit\': unsigned value 0 adjusted to 1',
       pos_in_log => 32,
       ts         => '080721  3:04:00',
      },
      {
       Serious    => 'Yes',
       arg        => '[ERROR] /usr/sbin/mysqld: unknown variable \'ssl-key=/opt/mysql.pdns/.cert/server-key.pem\'',
       pos_in_log => 119,
       ts         => '080721  3:04:01',
      },
      {
       arg        => 'mysqld ended',
       pos_in_log => 225,
       ts         => '080721 03:04:01',
      },
      {
       arg        => 'mysqld started',
       pos_in_log => 255,
       ts         => '080721 03:10:57',
      },
      {
       Serious    => 'No',
       arg        => '[Warning] No argument was provided to --log-bin, and --log-bin-index was not used; so replication may break when this MySQL server acts as a master and has his hostname changed!! Please use \'--log-bin=/var/run/mysqld/mysqld-bin\' to avoid this problem.',
       pos_in_log => 288,
       ts         => '080721  3:10:58',
      },
      {
       arg        => 'InnoDB: Started; log sequence number 1 3703096531',
       pos_in_log => 556,
       ts         => '080721  3:11:08',
      },
      {
       Serious    => 'No',
       arg        => '[Warning] Neither --relay-log nor --relay-log-index were used; so replication may break when this MySQL server acts as a slave and has his hostname changed!! Please use \'--relay-log=/var/run/mysqld/mysqld-relay-bin\' to avoid this problem.',
       pos_in_log => 878,
       ts         => '080721  3:11:12',
      },
      {
       Serious    => 'Yes',
       arg        => '[ERROR] Failed to open the relay log \'./srv-relay-bin.000001\' (relay_log_pos 4)',
       pos_in_log => 878,
       ts         => '080721  3:11:12',
      },
      {
       Serious    => 'Yes',
       arg        => '[ERROR] Could not find target log during relay log initialization',
       pos_in_log => 974,
       ts         => '080721  3:11:12',
      },
      {
       Serious    => 'Yes',
       arg        => '[ERROR] Failed to initialize the master info structure',
       pos_in_log => 1056,
       ts         => '080721  3:11:12',
      },
      {
       Serious    => 'No',
       arg        => '[Note] /usr/libexec/mysqld: ready for connections.',
       pos_in_log => 1127,
       ts         => '080721  3:11:12',
      },
      {
       arg        => 'Version: \'5.0.45-log\' socket: \'/mnt/data/mysql/mysql.sock\'  port: 3306  Source distribution',
       pos_in_log => 1194
      },
      {
       Serious    => 'No',
       arg        => '[Note] /usr/libexec/mysqld: Normal shutdown',
       pos_in_log => 1287,
       ts         => '080721  9:22:14',
      },
      {
       arg        => 'InnoDB: Starting shutdown...',
       pos_in_log => 1347,
       ts         => '080721  9:22:17',
      },
      {
       arg        => 'InnoDB: Shutdown completed; log sequence number 1 3703096531',
       pos_in_log => 1472,
       ts         => '080721  9:22:20',
      },
      {
       Serious    => 'No',
       arg        => '[Note] /usr/libexec/mysqld: Shutdown complete',
       pos_in_log => 1534,
       ts         => '080721  9:22:20',
      },
      {
       arg        => 'mysqld ended',
       pos_in_log => 1534,
       ts         => '080721 09:22:22',
      },
      {
       arg        => 'mysqld started',
       pos_in_log => 1565,
       ts         => '080721 09:22:31',
      },
      {
       arg        => 'Version: \'5.0.45-log\' socket: \'/mnt/data/mysql/mysql.sock\'  port: 3306  Source distribution',
       pos_in_log => 1598,
      },
      {
       Serious    => 'Yes',
       arg        => '[ERROR] bdb: log_archive: DB_ARCH_ABS: DB_NOTFOUND: No matching key/data pair found',
       pos_in_log => 1691,
       ts         => '080721  9:34:22',
      },
      {
       arg        => 'mysqld started',
       pos_in_log => 1792,
       ts         => '080721 09:39:09',
      },
      {
       arg        => 'InnoDB: Started; log sequence number 1 3703096531',
       pos_in_log => 1825,
       ts         => '080721  9:39:14',
      },
      {
       arg        => 'mysqld started',
       pos_in_log => 1924,
       ts         => '080821 19:14:12',
      },
      {
       pos_in_log => 1924,
       ts         => '080821 19:14:12',
       arg        => 'InnoDB: Database was not shut down normally! Starting crash recovery. Reading tablespace information from the .ibd files... Restoring possible half-written data pages from the doublewrite buffer...',
      },
      {
       pos_in_log => 2237,
       ts         => '080821 19:14:13',
       arg        => 'InnoDB: Starting log scan based on checkpoint at log sequence number 1 3703467071. Doing recovery: scanned up to log sequence number 1 3703467081 Last MySQL binlog file position 0 804759240, file name ./srv-bin.000012',
      },
      {
       arg        => 'InnoDB: Started; log sequence number 1 3703467081',
       pos_in_log => 2497,
       ts         => '080821 19:14:13',
      },
      {
       Serious    => 'No',
       arg        => '[Note] Recovering after a crash using srv-bin',
       pos_in_log => 2559,
       ts         => '080821 19:14:13',
      },
      {
       Serious    => 'No',
       arg        => '[Note] Starting crash recovery...',
       pos_in_log => 2559,
       ts         => '080821 19:14:23',
      },
      {
       Serious    => 'No',
       arg        => '[Note] Crash recovery finished.',
       pos_in_log => 2609,
       ts         => '080821 19:14:23',
      },
      {
       arg        => 'Version: \'5.0.45-log\' socket: \'/mnt/data/mysql/mysql.sock\'  port: 3306  Source distribution',
       pos_in_log => 2657,
      },
      {
       Serious    => 'No',
       arg        => '[Note] Found 5 of 0 rows when repairing \'./test/a3\'',
       pos_in_log => 2750,
       ts         => '080911 18:04:40',
      },
      {
       Serious    => 'No',
       arg        => '[Note] /usr/libexec/mysqld: ready for connections.',
       pos_in_log => 2818,
       ts         => '081101  9:17:53',
      },
      {
       arg        => 'Version: \'5.0.45-log\' socket: \'/mnt/data/mysql/mysql.sock\'  port: 3306  Source distribution',
       pos_in_log => 2886,
      },
      {
       arg        => 'Number of processes running now: 0',
       pos_in_log => 2979,
      },
      {
       arg        => 'mysqld restarted',
       pos_in_log => 3015,
       ts         => '081117 16:15:07',
      },
      {
       pos_in_log => 3049,
       ts         => '081117 16:15:16',
       Serious    => 'Yes',
       arg        => 'InnoDB: Error: cannot allocate 268451840 bytes of memory with malloc! Total allocated memory by InnoDB 8074720 bytes. Operating system errno: 12 Check if you should increase the swap file or ulimits of your operating system. On FreeBSD check you have compiled the OS with a big enough maximum process size. Note that in most 32-bit computers the process memory space is limited to 2 GB or 4 GB. We keep retrying the allocation for 60 seconds... Fatal error: cannot allocate the memory for the buffer pool',
      },
      {
       Serious    => 'No',
       arg        => '[Note] /usr/libexec/mysqld: ready for connections.',
       pos_in_log => 3718,
       ts         => '081117 16:32:55',
      },
   ],
});

# #############################################################################
# Done.
# #############################################################################
exit;
