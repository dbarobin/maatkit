# This program is copyright 2008-2009 Percona Inc.
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
# Daemon package $Revision$
# ###########################################################################

# Daemon - Daemonize and handle daemon-related tasks
package Daemon;

use strict;
use warnings FATAL => 'all';

use POSIX qw(setsid);
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG};

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      stdout   => $args{'stdout'} || '/dev/null',
      stderr   => $args{'stderr'} || undef,
      stdin    => $args{'stdin'}  || '/dev/null',
      PID_file => undef,  # set with create_PID_file()
   };
   MKDEBUG && _d('Daemonized child will redirect stdout to', $self->{stdout},
      'stderr to', $self->{stderr}, 'and stdin from', $self->{stdin});
   return bless $self, $class;
}

sub daemonize {
   my ( $self ) = @_;

   MKDEBUG && _d('About to fork and daemonize');
   defined (my $pid = fork()) or die "Cannot fork: $OS_ERROR";
   if ( $pid ) {
      MKDEBUG && _d('I am the parent and now I die');
      exit;
   }

   # I'm daemonized now.
   POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
   chdir '/' or die "Cannot chdir to /: $OS_ERROR";
   open STDOUT, ">$self->{stdout}"
      or die "Cannot redirect STDOUT to $self->{stdout}: $OS_ERROR";
   if ( $self->{stderr} ) {
      open STDERR, ">$self->{stderr}"
         or die "Cannot redirect STDERR to $self->{stderr}: $OS_ERROR";
   }
   open STDIN,  "$self->{stdin}",
      or die "Cannot redirect STDIN from $self->{stdin}: $OS_ERROR";
   MKDEBUG && _d('I am the child and now I live daemonized');
   return;
}

# PID_file must be set with this sub and not in new() because if it is
# already set then the parent will unlink it when its copy of the daemon
# obj is destoryed.
sub create_PID_file {
   my ( $self, $PID_file ) = @_;
   return unless $PID_file;
   $self->{PID_file} = $PID_file; # save for unlink in DESTORY()
   MKDEBUG && _d('PID file:', $self->{PID_file});
   open my $PID_FILE, '>', $self->{PID_file}
      or die "Cannot open PID file '$self->{PID_file}': $OS_ERROR";
   print $PID_FILE $PID;
   close $PID_FILE
      or die "Cannot close PID file '$self->{PID_file}': $OS_ERROR";
   return;
}

sub remove_PID_file {
   my ( $self ) = @_;
   if ( defined $self->{PID_file} && -f $self->{PID_file} ) {
      MKDEBUG && _d('Removing PID file');
      unlink $self->{PID_file}
         or warn "Cannot remove PID file '$self->{PID_file}': $OS_ERROR";
   }
   else {
      MKDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ( $self ) = @_;
   $self->remove_PID_file();
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Daemon package
# ###########################################################################
