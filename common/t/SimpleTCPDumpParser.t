#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use SimpleTCPDumpParser;
use MaatkitTest;

my $p = new SimpleTCPDumpParser(watch => ':3306');

# Check that I can parse a log in the default format.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/simpletcp001.txt',
   result => [
      {  ts         => '1301957863.804195',
         id         => 0,
         end        => '1301957863.804465',
         arg        => undef,
         host       => '10.10.18.253',
         port       => '58297',
         pos_in_log => 0,
      },
      {  ts         => '1301957863.805801',
         id         => 2,
         end        => '1301957863.806003',
         arg        => undef,
         host       => '10.10.18.253',
         port       => 52726,
         pos_in_log => 308,
      },
      {  ts         => '1301957863.805481',
         id         => 1,
         end        => '1301957863.806026',
         arg        => undef,
         host       => '10.10.18.253',
         port       => 40135,
         pos_in_log => 231,
      },
   ],
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;