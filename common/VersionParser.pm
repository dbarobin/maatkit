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
# ###########################################################################
# VersionParser package $Revision$
# ###########################################################################
use strict;
use warnings FATAL => 'all';

package VersionParser;

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG};

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub parse {
   my ( $self, $str ) = @_;
   my $result = sprintf('%03d%03d%03d', $str =~ m/(\d+)/g);
   MKDEBUG && _d("$str parses to $result");
   return $result;
}

# Compares versions like 5.0.27 and 4.1.15-standard-log.  Caches version number
# for each DBH for later use.
sub version_ge {
   my ( $self, $dbh, $target ) = @_;
   if ( !$self->{$dbh} ) {
      $self->{$dbh} = $self->parse(
         $dbh->selectrow_array('SELECT VERSION()'));
   }
   my $result = $self->{$dbh} ge $self->parse($target) ? 1 : 0;
   MKDEBUG && _d("$self->{$dbh} ge $target: $result");
   return $result;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   # Use $$ instead of $PID in case the package
   # does not use English.
   print "# $package:$line $$ ", @_, "\n";
}

1;

# ###########################################################################
# End VersionParser package
# ###########################################################################
