#!/usr/bin/perl

# This program is copyright 2008 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.

use strict;
use warnings FATAL => 'all';

use Test::More tests => 9;
use English qw(-no_match_vars);

use DBI;

require '../AggregateProcessList.pm';
require '../RecordsetFromText.pm';
require '../DSNParser.pm';
require '../MySQLDump.pm';
require '../Quoter.pm';
require '../TableParser.pm';

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

sub load_file {
   my ($file) = @_;
   open my $fh, "<", $file or die $!;
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   return $contents;
}

my $apl = AggregateProcessList->new();
isa_ok($apl, 'AggregateProcessList');

my $r = RecordsetFromText->new();
my $recset = $r->parse( load_file('samples/RecsetFromTxt-proclist_basic.txt') );
my $ag_pl = $apl->aggregate_processlist($recset);
is_deeply(
   $ag_pl,
   {
      command => { query     => { time => 0, count => 1 } },
      db      => { ''        => { time => 0, count => 1 } },
      user    => { msandbox  => { time => 0, count => 1 } },
      state   => { ''        => { time => 0, count => 1 } },
      host    => { localhost => { time => 0, count => 1 } },
   },
   'Aggregate basic processlist'
);

$recset = $r->parse(
   load_file('samples/RecsetFromTxt-proclist_vertical_51_rows.txt') );
$ag_pl = $apl->aggregate_processlist($recset);

is_deeply(
   $ag_pl,
   {  db => {
         NULL   => { count => 1,  time => 0 },
         forest => { count => 50, time => 529 }
      },
      user => {
         user1 => { count => 50, time => 529 },
         root  => { count => 1,  time => 0 }
      },
      host => {
         '0.1.2.11' => { count => 21, time => 183 },
         '0.1.2.12' => { count => 25, time => 331 },
         '0.1.2.21' => { count => 4,  time => 15 },
         localhost  => { count => 1,  time => 0 }
      },
      state => {
         locked    => { count => 24, time => 84 },
         preparing => { count => 26, time => 445 },
         null      => { count => 1,  time => 0 }
      },
      command => { query => { count => 51, time => 529 } }
   },
   'Sample with 51 processes',
);

exit;
