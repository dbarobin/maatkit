#!/usr/bin/perl

# This program is copyright (c) 2007 Baron Schwartz.
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

use Test::More tests => 6;
use English qw(-no_match_vars);
use DBI;

require "../ChangeHandler.pm";
require "../Quoter.pm";

sub throws_ok {
   my ( $code, $pat, $msg ) = @_;
   eval { $code->(); };
   like ( $EVAL_ERROR, $pat, $msg );
}

throws_ok(
   sub { new ChangeHandler() },
   qr/I need a quoter/,
   'Needs a quoter',
);

my @rows;
my $ch = new ChangeHandler(
   quoter   => new Quoter(),
   database => 'test',
   table    => 'foo',
   actions  => [ sub { push @rows, @_ } ],
);

$ch->change('INSERT', { a => 1, b => 2 }, [qw(a)] );

is_deeply(\@rows,
   ['INSERT INTO `test`.`foo`(`a`, `b`) VALUES (1, 2)',],
   'First row',
);

$ch->{queue} = 1;

$ch->change('DELETE', { a => 1, b => 2 }, [qw(a)] );

is_deeply(\@rows,
   ['INSERT INTO `test`.`foo`(`a`, `b`) VALUES (1, 2)',],
   'Second row not there yet',
);

$ch->process_rows(1);

is_deeply(\@rows,
   [
   'INSERT INTO `test`.`foo`(`a`, `b`) VALUES (1, 2)',
   'DELETE FROM `test`.`foo` WHERE `a`=1 LIMIT 1',
   ],
   'Second row there',
);
$ch->{queue} = 2;

$ch->change('UPDATE', { a => 1, b => 2 }, [qw(a)] );
$ch->process_rows(1);

is_deeply(\@rows,
   [
   'INSERT INTO `test`.`foo`(`a`, `b`) VALUES (1, 2)',
   'DELETE FROM `test`.`foo` WHERE `a`=1 LIMIT 1',
   ],
   'Third row not there',
);

$ch->process_rows();

is_deeply(\@rows,
   [
   'INSERT INTO `test`.`foo`(`a`, `b`) VALUES (1, 2)',
   'DELETE FROM `test`.`foo` WHERE `a`=1 LIMIT 1',
   'UPDATE `test`.`foo` SET `b`=2 WHERE `a`=1 LIMIT 1',
   ],
   'All rows',
);
