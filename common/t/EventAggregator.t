#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 17;
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

require '../QueryRewriter.pm';
require '../EventAggregator.pm';

my $qr = new QueryRewriter();
my ( $result, $events, $ea, $expected );

$ea = new EventAggregator(
   classes => {
      fingerprint => {
         Query_time => [qw(Query_time)],
         user       => [qw(user)],
         ts         => [qw(ts)],
         Rows_sent  => [qw(Rows_sent)],
      },
   },
);

isa_ok( $ea, 'EventAggregator' );

$events = [
   {  cmd           => 'Query',
      user          => 'root',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='foo'",
      Query_time    => '0.000652',
      Lock_time     => '0.000109',
      Rows_sent     => 1,
      Rows_examined => 1,
      pos_in_log    => 0,
   },
   {  ts   => '071015 21:43:52',
      cmd  => 'Query',
      user => 'root',
      host => 'localhost',
      ip   => '',
      arg =>
         "INSERT IGNORE INTO articles (id, body,)VALUES(3558268,'sample text')",
      Query_time    => '0.001943',
      Lock_time     => '0.000145',
      Rows_sent     => 0,
      Rows_examined => 0,
      pos_in_log    => 1,
   },
   {  ts            => '071015 21:43:52',
      cmd           => 'Query',
      user          => 'bob',
      host          => 'localhost',
      ip            => '',
      arg           => "SELECT id FROM users WHERE name='bar'",
      Query_time    => '0.000682',
      Lock_time     => '0.000201',
      Rows_sent     => 1,
      Rows_examined => 2,
      pos_in_log    => 5,
   }
];

$result = {
   fingerprint => {
      'select id from users where name=?' => {
         Query_time => {
            min => '0.000652',
            max => '0.000682',

            # all => [ '0.000652', '0.000682' ] # buckets 133, 134
            all =>
               [ ( map {0} ( 0 .. 132 ) ), 1, 1, ( map {0} ( 135 .. 999 ) ) ],
            sum => '0.001334',
            cnt => 2
         },
         user => {
            unq => {
               bob  => 1,
               root => 1
            },
            min => 'bob',
            max => 'root',
         },
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
            unq => { '071015 21:43:52' => 1, },
         },
         Rows_sent => {
            min => 1,
            max => 1,

            # all => [1, 1],
            all =>
               [ ( map {0} ( 0 .. 283 ) ), 2, ( map {0} ( 285 .. 999 ) ) ],
            sum => 2,
            cnt => 2,
         }
      },
      'insert ignore into articles (id, body,)values(?+)' => {
         Query_time => {
            min => '0.001943',
            max => '0.001943',

            # all => [ '0.001943' ],
            all =>
               [ ( map {0} ( 0 .. 155 ) ), 1, ( map {0} ( 157 .. 999 ) ) ],
            sum => '0.001943',
            cnt => 1
         },
         user => {
            unq => { root => 1 },
            min => 'root',
            max => 'root',
         },
         ts => {
            min => '071015 21:43:52',
            max => '071015 21:43:52',
            unq => { '071015 21:43:52' => 1, }
         },
         Rows_sent => {
            min => 0,
            max => 0,
            all =>
               [ ( map {0} ( 0 .. 283 ) ), 1, ( map {0} ( 285 .. 999 ) ) ],
            sum => 0,
            cnt => 1,
         }
      }
   },
};

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}

is_deeply( $ea->results->{classes},
   $result, 'Simple fingerprint aggregation' );

$ea = new EventAggregator(
   classes => {},
   globals => {
      Query_time => [qw(Query_time)],
      user       => [qw(user)],
      ts         => [qw(ts)],
      Rows_sent  => [qw(Rows_sent)],
   },
);

$result = {
   Query_time => {
      min => '0.000652',
      max => '0.001943',
      sum => '0.003277',
      cnt => 3,
      all => [
         ( map {0} ( 0 .. 132 ) ),
         1, 1, ( map {0} ( 135 .. 155 ) ),
         1, ( map {0} ( 157 .. 999 ) ),
      ],
   },
   user => {
      min => 'bob',
      max => 'root',
   },
   ts => {
      min => '071015 21:43:52',
      max => '071015 21:43:52',
   },
   Rows_sent => {
      min => 0,
      max => 1,
      sum => 2,
      cnt => 3,
      all => [ ( map {0} ( 0 .. 283 ) ), 3, ( map {0} ( 285 .. 999 ) ), ],
   },
};

foreach my $event (@$events) {
   $event->{fingerprint} = $qr->fingerprint( $event->{arg} );
   $ea->aggregate($event);
}

is_deeply( $ea->results->{globals},
   $result, 'Simple fingerprint aggregation all' );

# #############################################################################
# Test that the sample of the worst occurrence is saved.
# #############################################################################

$ea = new EventAggregator(
   classes => { arg => { Query_time => [qw(Query_time)], }, },
   save    => 'Query_time',
);

$events = [
   {  user       => 'bob',
      arg        => "foo 1",
      Query_time => '1',
   },
   {  user       => 'root',
      arg        => "foo 1",
      Query_time => '5',
   }
];

foreach my $event (@$events) {
   $ea->aggregate($event);
}

is($ea->results->{classes}->{arg}->{'foo 1'}->{Query_time}->{sample}->{user},
   'root', "Keeps the worst sample"
);

# #############################################################################
# Test bucketizing a straightforward list.
# #############################################################################
is_deeply(
   [ $ea->bucketize( [ 2, 3, 6, 4, 8, 9, 1, 1, 1, 5, 4, 3, 1 ] ) ],
   [  [  ( map {0} ( 0 .. 283 ) ),
         4,
         ( map {0} ( 285 .. 297 ) ),
         1,
         ( map {0} ( 299 .. 305 ) ),
         2,
         ( map {0} ( 307 .. 311 ) ),
         2, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1,
         ( map {0} ( 330 .. 999 ) ),
      ],
      {  sum => 48,
         max => 9,
         min => 1,
         cnt => 13,
      },
   ],
   'Bucketizes values right',
);

is_deeply(
   [  $ea->unbucketize(
         $ea->bucketize( [ 2, 3, 6, 4, 8, 9, 1, 1, 1, 5, 4, 3, 1 ] )
      )
   ],

   # If there were no loss of precision, we'd get this:
   # [1, 1, 1, 1, 2, 3, 3, 4, 4, 5, 6, 8, 9]
   # But we have only 5% precision in the buckets, so...
   [  '1.04174382747661', '1.04174382747661',
      '1.04174382747661', '1.04174382747661',
      '2.06258152254188', '3.04737229873823',
      '3.04737229873823', '4.08377033290049',
      '4.08377033290049', '4.96384836320513',
      '6.03358870952811', '8.08558592696284',
      '9.36007640870036'
   ],
   "Unbucketizes okay",
);

# #############################################################################
# Test statistical metrics: 95%, stddev, and median
# #############################################################################

$result = $ea->calculate_statistical_metrics(
   $ea->bucketize( [ 2, 3, 6, 4, 8, 9, 1, 1, 1, 5, 4, 3, 1 ] ) );
is_deeply(
   $result,
   {  stddev => 2.26493026699131,
      median => 3.04737229873823,
      cutoff => 12,
      pct_95 => 8.08558592696284,
   },
   'Calculates statistical metrics'
);

$result = $ea->calculate_statistical_metrics(
   $ea->bucketize( [ 1, 1, 1, 1, 2, 3, 4, 4, 4, 4, 6, 8, 9 ] ) );

# 95th pct: --------------------------^
# median:------------------^ = 3.5
is_deeply(
   $result,
   {  stddev => 2.23248737175256,
      median => 3.56557131581936,
      cutoff => 12,
      pct_95 => 8.08558592696284,
   },
   'Calculates median when it is halfway between two elements',
);

# This is a special case: only two values, widely separated.  The median should
# be exact (because we pass in min/max) and the stdev should never be bigger
# than half the difference between min/max.
$result = $ea->calculate_statistical_metrics(
   $ea->bucketize( [ 0.000002, 0.018799 ] ) );
is_deeply(
   $result,
   {  stddev => 0.0132914861659635,
      median => 0.0094005,
      cutoff => 2,
      pct_95 => 0.018799,
   },
   'Calculates stats for two-element special case',
);

$result = $ea->calculate_statistical_metrics(undef);
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for undef array'
);

$result = $ea->calculate_statistical_metrics( [] );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for empty array'
);

$result = $ea->calculate_statistical_metrics( [ 1, 2 ], {} );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0,
      cutoff => undef,
      pct_95 => 0,
   },
   'Calculates statistical metrics for when $stats missing'
);

$result = $ea->calculate_statistical_metrics( $ea->bucketize( [0.9] ) );
is_deeply(
   $result,
   {  stddev => 0,
      median => 0.9,
      cutoff => 1,
      pct_95 => 0.9,
   },
   'Calculates statistical metrics for 1 value'
);

# #############################################################################
# Make sure it doesn't die when I try to parse an event that doesn't have an
# expected attribute.
# #############################################################################
eval { $ea->aggregate( { fingerprint => 'foo' } ); };
is( $EVAL_ERROR, '', "Handles an undef attrib OK" );

# #############################################################################
# Issue 184: db OR Schema
# #############################################################################
$ea = new EventAggregator( classes => { arg => { db => [qw(db Schema)], }, },
);

$events = [
   {  arg    => "foo1",
      Schema => 'db1',
   },
   {  arg => "foo2",
      db  => 'db1',
   },
];
foreach my $event (@$events) {
   $ea->aggregate($event);
}

is( $ea->results->{classes}->{arg}->{foo1}->{db}->{min},
   'db1', 'Gets Schema for db|Schema (issue 184)' );

is( $ea->results->{classes}->{arg}->{foo2}->{db}->{min},
   'db1', 'Gets db for db|Schema (issue 184)' );

# #############################################################################
# Make sure large values are kept reasonable.
# #############################################################################
$ea = new EventAggregator(
   classes      => { arg       => { Rows_read => [qw(Rows_read)], }, },
   globals      => { Rows_read => [qw(Rows_read)], },
   attrib_limit => 1000,
);

$events = [
   {  arg       => "arg1",
      Rows_read => 4,
   },
   {  arg       => "arg2",
      Rows_read => 4124524590823728995,
   },
   {  arg       => "arg1",
      Rows_read => 4124524590823728995,
   },
];

foreach my $event (@$events) {
   $ea->aggregate($event);
}

$result = {
   classes => {
      arg => {
         'arg1' => {
            Rows_read => {
               min => 4,
               max => 4,
               all =>
                  [ ( map {0} ( 0 .. 311 ) ), 2, ( map {0} ( 313 .. 999 ) ) ],
               sum    => 8,
               cnt    => 2,
               'last' => 4,
            }
         },
         'arg2' => {
            Rows_read => {
               min => 0,
               max => 0,
               all =>
                  [ ( map {0} ( 0 .. 283 ) ), 1, ( map {0} ( 285 .. 999 ) ) ],
               sum    => 0,
               cnt    => 1,
               'last' => 0,
            }
         },
      },
   },
   globals => {
      Rows_read => {
         min => 4,
         max => 4,
         all => [ ( map {0} ( 0 .. 311 ) ), 3, ( map {0} ( 313 .. 999 ) ) ],
         sum => 12,
         cnt => 3,
         'last' => 4,
      },
   },
};

is_deeply( $ea->results, $result, 'Limited attribute values', );
