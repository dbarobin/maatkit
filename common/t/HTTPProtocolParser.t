#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 10;

require '../TcpdumpParser.pm';
require '../ProtocolParser.pm';
require '../HTTPProtocolParser.pm';

use Data::Dumper;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Indent    = 1;

my $tcpdump  = new TcpdumpParser();
my $protocol; # Create a new HTTPProtocolParser for each test.

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
   my $num_events = 0;

   my @callbacks;
   push @callbacks, sub {
      my ( $packet ) = @_;
      return $protocol->parse_packet($packet, undef);
   };
   push @callbacks, sub {
      push @e, @_;
   };

   eval {
      open my $fh, "<", $def->{file}
         or BAIL_OUT("Cannot open $def->{file}: $OS_ERROR");
      $num_events++ while $tcpdump->parse_event($fh, undef, @callbacks);
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
      is($num_events, $def->{num_events}, "$def->{file} num_events");
   }

   # Uncomment this if you're hacking the unknown.
   # print "Events for $def->{file}: ", Dumper(\@e);

   return;
}

# GET a very simple page.
$protocol = new HTTPProtocolParser();
run_test({
   file   => 'samples/http_tcpdump001.txt',
   result => [
      { ts              => '2009-11-09 11:31:52.341907',
        bytes           => '715',
        host            => '10.112.2.144',
        pos_in_log      => 0,
        Virtual_host    => 'hackmysql.com',
        arg             => 'get /contact',
        Status_code     => '200',
        Query_time      => '0.651419',
        Transmit_time   => '0.000000',
      },
   ],
});

# Get http://www.percona.com/about-us.html
$protocol = new HTTPProtocolParser();
run_test({
   file   => 'samples/http_tcpdump002.txt',
   result => [
      {
         ts             => '2009-11-09 15:31:09.074855',
         Query_time     => '0.070097',
         Status_code    => '200',
         Transmit_time  => '0.000720',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /about-us.html',
         bytes          => 3832,
         host           => '10.112.2.144',
         pos_in_log     => 206,
      },
      {
         ts             => '2009-11-09 15:31:09.157215',
         Query_time     => '0.068558',
         Status_code    => '200',
         Transmit_time  => '0.066490',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /js/jquery.js',
         bytes          => 9921,
         host           => '10.112.2.144',
         pos_in_log     => 16362,
      },
      {
         ts             => '2009-11-09 15:31:09.346763',
         Query_time     => '0.066506',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /images/menu_team.gif',
         bytes          => 344,
         host           => '10.112.2.144',
         pos_in_log     => 53100,
      },
      {
         ts             => '2009-11-09 15:31:09.373800',
         Query_time     => '0.045442',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.google-analytics.com',
         arg            => 'get /__utm.gif?utmwv=1.3&utmn=1710381507&utmcs=UTF-8&utmsr=1280x800&utmsc=24-bit&utmul=en-us&utmje=1&utmfl=10.0%20r22&utmdt=About%20Percona&utmhn=www.percona.com&utmhid=1947703805&utmr=0&utmp=/about-us.html&utmac=UA-343802-3&utmcc=__utma%3D154442809.1969570579.1256593671.1256825719.1257805869.3%3B%2B__utmz%3D154442809.1256593671.1.1.utmccn%3D(direct)%7Cutmcsr%3D(direct)%7Cutmcmd%3D(none)%3B%2B',
         bytes          => 35,
         host           => '10.112.2.144',
         pos_in_log     => 55942,
      },
      {
         ts             => '2009-11-09 15:31:09.411349',
         Query_time     => '0.073882',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /images/menu_our-vision.gif',
         bytes          => 414,
         host           => '10.112.2.144',
         pos_in_log     => 59213,
      },
      {
         ts             => '2009-11-09 15:31:09.420851',
         Query_time     => '0.067669',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /images/bg-gray-corner-top.gif',
         bytes          => 170,
         host           => '10.112.2.144',
         pos_in_log     => 65644,
      },
      {
         ts             => '2009-11-09 15:31:09.420996',
         Query_time     => '0.067345',
         Status_code    => '200',
         Transmit_time  => '0.134909',
         Virtual_host   => 'www.percona.com',
         arg            => 'get /images/handshake.jpg',
         bytes          => 20017,
         host           => '10.112.2.144',
         pos_in_log     => 67956,
      },
      {
         ts             => '2009-11-09 15:31:14.536149',
         Query_time     => '0.061528',
         Status_code    => '200',
         Transmit_time  => '0.059577',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get /clickaider.js',
         bytes          => 4009,
         host           => '10.112.2.144',
         pos_in_log     => 147447,
      },
      {
         ts             => '2009-11-09 15:31:14.678713',
         Query_time     => '0.060436',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get /pv?lng=140&&lnks=&t=About%20Percona&c=73a41b95-2926&r=http%3A%2F%2Fwww.percona.com%2F&tz=-420&loc=http%3A%2F%2Fwww.percona.com%2Fabout-us.html&rnd=3688',
         bytes          => 43,
         host           => '10.112.2.144',
         pos_in_log     => 167245,
      },
      {
         ts             => '2009-11-09 15:31:14.737890',
         Query_time     => '0.061937',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get /s/forms.js',
         bytes          => 822,
         host           => '10.112.2.144',
         pos_in_log     => 170117,
      },
   ],
});

# A reponse received in out of order packet.
$protocol = new HTTPProtocolParser();
run_test({
   file   => 'samples/http_tcpdump004.txt',
   result => [
      {  ts             => '2009-11-12 11:27:10.757573',
         Query_time     => '0.327356',
         Status_code    => '200',
         Transmit_time  => '0.549501',
         Virtual_host   => 'dev.mysql.com',
         arg            => 'get /common/css/mysql.css',
         bytes          => 11283,
         host           => '10.67.237.92',
         pos_in_log     => 776,
      },
   ],
});

# A client request broken over 2 packets.
$protocol = new HTTPProtocolParser();
run_test({
   file   => 'samples/http_tcpdump005.txt',
   result => [
      {  ts             => '2009-11-13 09:20:31.041924',
         Query_time     => '0.342166',
         Status_code    => '200',
         Transmit_time  => '0.012780',
         Virtual_host   => 'dev.mysql.com',
         arg            => 'get /doc/refman/5.0/fr/retrieving-data.html',
         bytes          => 4382,
         host           => '192.168.200.110',
         pos_in_log     => 785, 
      },
   ],
});

# Out of order header that might look like the text header
# but is really data; text header arrives last.
$protocol = new HTTPProtocolParser();
run_test({
   file   => 'samples/http_tcpdump006.txt',
   result => [
      {  ts             => '2009-11-13 09:50:44.432099',
         Query_time     => '0.140878',
         Status_code    => '200',
         Transmit_time  => '0.237153',
         Virtual_host   => '247wallst.files.wordpress.com',
         arg            => 'get /2009/11/airplane4.jpg?w=139&h=93',
         bytes          => 3391,
         host           => '192.168.200.110',
         pos_in_log     => 782,
      },
   ],
});

# #############################################################################
# Done.
# #############################################################################
exit;
