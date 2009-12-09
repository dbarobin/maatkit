#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 51;
use English qw(-no_match_vars);

require "../MySQLProtocolParser.pm";
require "../TcpdumpParser.pm";
require '../MaatkitTest.pm';

MaatkitTest->import('load_file');

use Data::Dumper;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Indent    = 1;

my $tcpdump  = new TcpdumpParser();
my $protocol; # Create a new MySQLProtocolParser for each test.

sub load_data {
   my ( $file ) = @_;
   open my $fh, '<', $file or BAIL_OUT("Cannot open $file: $OS_ERROR");
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   (my $data = join('', $contents =~ m/(.*)/g)) =~ s/\s+//g;
   return $data;
}

sub run_test {
   my ( $def ) = @_;
   map     { die "What is $_ for?" }
      grep { $_ !~ m/^(?:misc|file|result|num_events|desc)$/ }
      keys %$def;
   my @e;
   eval {
      open my $fh, "<", $def->{file}
         or BAIL_OUT("Cannot open $def->{file}: $OS_ERROR");
      my %args = (
         fh   => $fh,
         misc => $def->{misc},
      );
      while ( my $p = $tcpdump->parse_event(%args) ) {
         my $e = $protocol->parse_event(%args, event => $p);
         push @e, $e if $e;
      }
      close $fh;
   };
   is($EVAL_ERROR, '', "No error on $def->{file}");
   if ( defined $def->{result} ) {
      is_deeply(
         \@e,
         $def->{result},
         $def->{file} . ($def->{desc} ? ": $def->{desc}" : '')
      ) or print "Got: ", Dumper(\@e);
   }
   if ( defined $def->{num_events} ) {
      is(scalar @e, $def->{num_events}, "$def->{file} num_events");
   }
}

# Check that I can parse a really simple session.
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump001.txt',
   result => [
      {  ts            => '090412 09:50:16.805123',
         db            => undef,
         user          => undef,
         Thread_id     => 4294967296,
         host          => '127.0.0.1',
         ip            => '127.0.0.1',
         port          => '42167',
         arg           => 'select "hello world" as greeting',
         Query_time    => sprintf('%.6f', .805123 - .804849),
         pos_in_log    => 0,
         bytes         => length('select "hello world" as greeting'),
         cmd           => 'Query',
         Error_no      => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# A more complex session with a complete login/logout cycle.
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump002.txt',
   result => [
      {  ts         => "090412 11:00:13.118191",
         db         => 'mysql',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         arg        => 'administrator command: Connect',
         Query_time => '0.011152',
         Thread_id  => 8,
         pos_in_log => 1470,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Error_no   => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000265',
         Thread_id  => 8,
         arg        => 'select @@version_comment limit 1',
         bytes      => length('select @@version_comment limit 1'),
         cmd        => 'Query',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 2449,
         ts         => '090412 11:00:13.118643',
         user       => 'msandbox',
         Error_no   => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000167',
         Thread_id  => 8,
         arg        => 'select "paris in the the spring" as trick',
         bytes      => length('select "paris in the the spring" as trick'),
         cmd        => 'Query',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => 3298,
         ts         => '090412 11:00:13.119079',
         user       => 'msandbox',
         Error_no   => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Query_time => '0.000000',
         Thread_id  => 8,
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         db         => 'mysql',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '57890',
         pos_in_log => '4186',
         ts         => '090412 11:00:13.119487',
         user       => 'msandbox',
         Error_no   => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# A session that has an error during login.
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump003.txt',
   result => [
      {  ts         => "090412 12:41:46.357853",
         db         => '',
         user       => 'msandbox',
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '44488',
         arg        => 'administrator command: Connect',
         Query_time => '0.010753',
         Thread_id  => 9,
         pos_in_log => 1455,
         bytes      => length('administrator command: Connect'),
         cmd        => 'Admin',
         Error_no   => "#1045",
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# A session that has an error executing a query
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump004.txt',
   result => [
      {  ts         => "090412 12:58:02.036002",
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '60439',
         arg        => 'select 5 from foo',
         Query_time => '0.000251',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('select 5 from foo'),
         cmd        => 'Query',
         Error_no   => "#1046",
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# A session that has a single-row insert and a multi-row insert
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump005.txt',
   result => [
      {  Error_no   => 'none',
         Rows_affected => 1,
         Query_time => '0.000435',
         Thread_id  => 4294967296,
         arg        => 'insert into test.t values(1)',
         bytes      => 28,
         cmd        => 'Query',
         db         => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '55300',
         pos_in_log => '0',
         ts         => '090412 16:46:02.978340',
         user       => undef,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
      {  Error_no   => 'none',
         Rows_affected => 2,
         Query_time => '0.000565',
         Thread_id  => 4294967296,
         arg        => 'insert into test.t values(1),(2)',
         bytes      => 32,
         cmd        => 'Query',
         db         => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '55300',
         pos_in_log => '1033',
         ts         => '090412 16:46:20.245088',
         user       => undef,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# A session that causes a slow query because it doesn't use an index.
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump006.txt',
   result => [
      {  ts         => '100412 20:46:10.776899',
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '48259',
         arg        => 'select * from t',
         Query_time => '0.000205',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('select * from t'),
         cmd        => 'Query',
         Error_no   => 'none',
         Rows_affected      => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'Yes',
      },
   ],
});

# A session that truncates an insert.
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump007.txt',
   result => [
      {  ts         => '090412 20:57:22.798296',
         db         => undef,
         user       => undef,
         host       => '127.0.0.1',
         ip         => '127.0.0.1',
         port       => '38381',
         arg        => 'insert into t values(current_date)',
         Query_time => '0.000020',
         Thread_id  => 4294967296,
         pos_in_log => 0,
         bytes      => length('insert into t values(current_date)'),
         cmd        => 'Query',
         Error_no   => 'none',
         Rows_affected      => 1,
         Warning_count      => 1,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# #############################################################################
# Check the individual packet parsing subs.
# #############################################################################
MySQLProtocolParser->import(qw(
   parse_error_packet
   parse_ok_packet
   parse_server_handshake_packet
   parse_client_handshake_packet
   parse_com_packet
));
 
is_deeply(
   parse_error_packet(load_data('samples/mysql_proto_001.txt')),
   {
      errno    => '1046',
      sqlstate => '#3D000',
      message  => 'No database selected',
   },
   'Parse error packet'
);

is_deeply(
   parse_ok_packet('010002000100'),
   {
      affected_rows => 1,
      insert_id     => 0,
      status        => 2,
      warnings      => 1,
      message       => '',
   },
   'Parse ok packet'
);

is_deeply(
   parse_server_handshake_packet(load_data('samples/mysql_proto_002.txt')),
   {
      thread_id      => '9',
      server_version => '5.0.67-0ubuntu6-log',
      flags          => {
         CLIENT_COMPRESS          => 1,
         CLIENT_CONNECT_WITH_DB   => 1,
         CLIENT_FOUND_ROWS        => 0,
         CLIENT_IGNORE_SIGPIPE    => 0,
         CLIENT_IGNORE_SPACE      => 0,
         CLIENT_INTERACTIVE       => 0,
         CLIENT_LOCAL_FILES       => 0,
         CLIENT_LONG_FLAG         => 1,
         CLIENT_LONG_PASSWORD     => 0,
         CLIENT_MULTI_RESULTS     => 0,
         CLIENT_MULTI_STATEMENTS  => 0,
         CLIENT_NO_SCHEMA         => 0,
         CLIENT_ODBC              => 0,
         CLIENT_PROTOCOL_41       => 1,
         CLIENT_RESERVED          => 0,
         CLIENT_SECURE_CONNECTION => 1,
         CLIENT_SSL               => 0,
         CLIENT_TRANSACTIONS      => 1,
      }
   },
   'Parse server handshake packet'
);

is_deeply(
   parse_client_handshake_packet(load_data('samples/mysql_proto_003.txt')),
   {
      db    => 'mysql',
      user  => 'msandbox',
      flags => {
         CLIENT_COMPRESS          => 0,
         CLIENT_CONNECT_WITH_DB   => 1,
         CLIENT_FOUND_ROWS        => 0,
         CLIENT_IGNORE_SIGPIPE    => 0,
         CLIENT_IGNORE_SPACE      => 0,
         CLIENT_INTERACTIVE       => 0,
         CLIENT_LOCAL_FILES       => 1,
         CLIENT_LONG_FLAG         => 1,
         CLIENT_LONG_PASSWORD     => 1,
         CLIENT_MULTI_RESULTS     => 1,
         CLIENT_MULTI_STATEMENTS  => 1,
         CLIENT_NO_SCHEMA         => 0,
         CLIENT_ODBC              => 0,
         CLIENT_PROTOCOL_41       => 1,
         CLIENT_RESERVED          => 0,
         CLIENT_SECURE_CONNECTION => 1,
         CLIENT_SSL               => 0,
         CLIENT_TRANSACTIONS      => 1,
      },
   },
   'Parse client handshake packet'
);

is_deeply(
   parse_com_packet('0373686f77207761726e696e67738d2dacbc', 14),
   {
      code => '03',
      com  => 'COM_QUERY',
      data => 'show warnings',
   },
   'Parse COM_QUERY packet'
);

# Test that we can parse with a non-standard port etc.
$protocol = new MySQLProtocolParser(
   server => '192.168.1.1:3307',
);
run_test({
   file   => 'samples/tcpdump012.txt',
   result => [
      {  ts            => '090412 09:50:16.805123',
         db            => undef,
         user          => undef,
         Thread_id     => 4294967296,
         host          => '127.0.0.1',
         ip            => '127.0.0.1',
         port          => '42167',
         arg           => 'select "hello world" as greeting',
         Query_time    => sprintf('%.6f', .805123 - .804849),
         pos_in_log    => 0,
         bytes         => length('select "hello world" as greeting'),
         cmd           => 'Query',
         Error_no      => 'none',
         Rows_affected => 0,
         Warning_count      => 0,
         No_good_index_used => 'No',
         No_index_used      => 'No',
      },
   ],
});

# #############################################################################
# Issue 447: MySQLProtocolParser does not handle old password algo or
# compressed packets  
# #############################################################################
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15:3306',
);
run_test({
   file   => 'samples/tcpdump013.txt',
   desc   => 'old password and compression',
   result => [
      {  Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.034355',
         Rows_affected => 0,
         Thread_id => 36947020,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => '',
         host => '10.54.212.171',
         ip => '10.54.212.171',
         port => '49663',
         pos_in_log => 1834,
         ts => '090603 10:52:24.578817',
         user => 'luck'
      },
   ],
});

# Check in-stream compression detection.
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15:3306',
);
run_test({
   file   => 'samples/tcpdump014.txt',
   desc   => 'in-stream compression detection',
   result => [
      {
         Error_no           => 'none',
         No_good_index_used => 'No',
         No_index_used      => 'No',
         Query_time         => '0.001375',
         Rows_affected      => 0,
         Thread_id          => 4294967296,
         Warning_count      => 0,
         arg                => 'show databases',
         bytes              => 14,
         cmd                => 'Query',
         db                 => undef,
         host               => '10.54.212.171',
         ip                 => '10.54.212.171',
         port               => '49663',
         pos_in_log         => 0,
         ts                 => '090603 10:52:24.587685',
         user               => undef,
      },
   ],
});

# Check data decompression.
$protocol = new MySQLProtocolParser(
   server => '127.0.0.1:12345',
);
run_test({
   file   => 'samples/tcpdump015.txt',
   desc   => 'compressed data',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.006415',
         Rows_affected => 0,
         Thread_id => 20,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44489',
         pos_in_log => 664,
         ts => '090612 08:39:05.316805',
         user => 'msandbox',
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.002884',
         Rows_affected => 0,
         Thread_id => 20,
         Warning_count => 0,
         arg => 'select * from help_relation',
         bytes => 27,
         cmd => 'Query',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44489',
         pos_in_log => 1637,
         ts => '090612 08:39:08.428913',
         user => 'msandbox',
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => 20,
         Warning_count => 0,
         arg => 'administrator command: Quit',
         bytes => 27,
         cmd => 'Admin',
         db => 'mysql',
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44489',
         pos_in_log => 15782,
         ts => '090612 08:39:09.145334',
         user => 'msandbox',
      },
   ],
});

# TCP retransmission.
# Check data decompression.
$protocol = new MySQLProtocolParser(
   server => '10.55.200.15:3306',
);
run_test({
   file   => 'samples/tcpdump016.txt',
   desc   => 'TCP retransmission',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.001000',
         Rows_affected => 0,
         Thread_id => 38559282,
         Warning_count => 0,
         arg => 'administrator command: Connect',
         bytes => 30,
         cmd => 'Admin',
         db => '',
         host => '10.55.200.31',
         ip => '10.55.200.31',
         port => '64987',
         pos_in_log => 468,
         ts => '090609 16:53:17.112346',
         user => 'ppppadri',
      },
   ],
});

# #############################################################################
# Issue 537: MySQLProtocolParser and MemcachedProtocolParser do not handle
# multiple servers.
# #############################################################################
$protocol = new MySQLProtocolParser();
run_test({
   file   => 'samples/tcpdump018.txt',
   desc   => 'Multiple servers',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000206',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'select * from foo',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '42275',
         pos_in_log => 0,
         ts => '090727 08:28:41.723651',
         user => undef,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000203',
         Rows_affected => 0,
         Thread_id => '4294967297',
         Warning_count => 0,
         arg => 'select * from bar',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '34233',
         pos_in_log => 987,
         ts => '090727 08:29:34.232748',
         user => undef,
      },
   ],
});

# Test that --watch-server causes just the given server to be watched.
$protocol = new MySQLProtocolParser(server=>'10.0.0.1:3306');
run_test({
   file   => 'samples/tcpdump018.txt',
   desc   => 'Multiple servers but watch only one',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000206',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'select * from foo',
         bytes => 17,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '42275',
         pos_in_log => 0,
         ts => '090727 08:28:41.723651',
         user => undef,
      },
   ]
});


# #############################################################################
# Issue 558: Make mk-query-digest handle big/fragmented packets
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
{
   my $file = 'samples/tcpdump019.txt';
   my @e;
   eval {
      open my $fh, "<", $file
         or BAIL_OUT("Cannot open $file: $OS_ERROR");
      my %args = (
         fh   => $fh,
      );
      while ( my $p = $tcpdump->parse_event(%args) ) {
         my $e = $protocol->parse_event(%args, event => $p);
         push @e, $e if $e;
      }
      close $fh;
   };

   like(
      $e[0]->{arg},
      qr/--THE END--'\)$/,
      'Handles big, fragmented MySQL packets (issue 558)'
   );

   my $arg = load_file('samples/tcpdump019-arg.txt');
   chomp $arg;
   is(
      $e[0]->{arg},
      $arg,
      'Re-assembled data is correct (issue 558)'
   );
}

# #############################################################################
# Issue 740: Handle prepared statements
# #############################################################################
$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump021.txt',
   desc   => 'prepared statements, simple, no NULL',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000286',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT i FROM d.t WHERE i=?',
         bytes => 35,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '58619',
         pos_in_log => 0,
         ts => '091208 09:23:49.637394',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000281',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT i FROM d.t WHERE i=3',
         bytes => 27,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '58619',
         pos_in_log => 1106,
         ts => '091208 09:23:49.637892',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
          No_good_index_used => 'No',
          No_index_used => 'No',
          Query_time => '0.000000',
          Rows_affected => 0,
          Thread_id => '4294967296',
          Warning_count => 0,
          arg => 'administrator command: Quit',
          bytes => 27,
          cmd => 'Admin',
          db => undef,
          host => '127.0.0.1',
          ip => '127.0.0.1',
          port => '58619',
          pos_in_log => 1850,
          ts => '091208 09:23:49.638381',
          user => undef
      },
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump022.txt',
   desc   => 'prepared statements, NULL value',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000303',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT i,j FROM d.t2 WHERE i=? AND j=?',
         bytes => 46,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44545',
         pos_in_log => 0,
         ts => '091208 13:41:12.811188',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000186',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT i,j FROM d.t2 WHERE i=NULL AND j=5',
         bytes => 41,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '44545',
         pos_in_log => 1330,
         ts => '091208 13:41:12.811591',
         user => undef,
         Statement_id => 2,
      }
      ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump023.txt',
   desc   => 'prepared statements, string, char and float',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000315',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t3 WHERE v=? OR c=? OR f=?',
         bytes => 50,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '49806',
         pos_in_log => 0,
         ts => '091208 14:14:55.951863',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000249',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t3 WHERE v="hello world" OR c="a" OR f=1.23',
         bytes => 59,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '49806',
         pos_in_log => 1540,
         ts => '091208 14:14:55.952344',
         user => undef,
         Statement_id => 2,
      }
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump024.txt',
   desc   => 'prepared statements, all NULL',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000278',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t3 WHERE v=? OR c=? OR f=?',
         bytes => 50,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '32810',
         pos_in_log => 0,
         ts => '091208 14:33:13.711351',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000159',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t3 WHERE v=NULL OR c=NULL OR f=NULL',
         bytes => 51,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '32810',
         pos_in_log => 1540,
         ts => '091208 14:33:13.711642',
         user => undef,
         Statement_id => 2,
      },
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump025.txt',
   desc   => 'prepared statements, no params',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000268',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE 1 LIMIT 1;',
         bytes => 42,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '48585',
         pos_in_log => 0,
         ts => '091208 14:44:52.709181',
         user => undef,
         Statement_id => 2,
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000234',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t WHERE 1 LIMIT 1;',
         bytes => 34,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '48585',
         pos_in_log => 1014,
         ts => '091208 14:44:52.709597',
         user => undef,
         Statement_id => 2,
      }
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:3306');
run_test({
   file   => 'samples/tcpdump026.txt',
   desc   => 'prepared statements, close statement',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000000',
         Rows_affected => 0,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'DEALLOCATE PREPARE 50',
         bytes => 21,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '34162',
         pos_in_log => 0,
         ts => '091208 17:42:12.696547',
         user => undef
      }
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:3306');
run_test({
   file   => 'samples/tcpdump027.txt',
   desc   => 'prepared statements, reset statement',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000023',
         Rows_affected => 0,
         Statement_id => 51,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'RESET 51',
         bytes => 8,
         cmd => 'Query',
         db => undef,
         host => '1.2.3.4',
         ip => '1.2.3.4',
         port => '34162',
         pos_in_log => 0,
         ts => '091208 17:42:12.698093',
         user => undef
      }
   ],
});

$protocol = new MySQLProtocolParser(server=>'127.0.0.1:12345');
run_test({
   file   => 'samples/tcpdump028.txt',
   desc   => 'prepared statements, multiple exec, new param',
   result => [
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'No',
         Query_time => '0.000292',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'PREPARE SELECT * FROM d.t WHERE i=?',
         bytes => 35,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 0,
         ts => '091208 17:35:37.433248',
         user => undef
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000254',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t WHERE i=1',
         bytes => 27,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 1106,
         ts => '091208 17:35:37.433700',
         user => undef
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000190',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t WHERE i=3',
         bytes => 27,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 1850,
         ts => '091208 17:35:37.434303',
         user => undef
      },
      {
         Error_no => 'none',
         No_good_index_used => 'No',
         No_index_used => 'Yes',
         Query_time => '0.000166',
         Rows_affected => 0,
         Statement_id => 2,
         Thread_id => '4294967296',
         Warning_count => 0,
         arg => 'SELECT * FROM d.t WHERE i=NULL',
         bytes => 30,
         cmd => 'Query',
         db => undef,
         host => '127.0.0.1',
         ip => '127.0.0.1',
         port => '38682',
         pos_in_log => 2589,
         ts => '091208 17:35:37.434708',
         user => undef
      }
   ],
});

# #############################################################################
# Done.
# #############################################################################
exit;
