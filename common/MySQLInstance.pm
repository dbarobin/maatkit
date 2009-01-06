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
# ###########################################################################
# MySQLInstance package $Revision$
# ###########################################################################

# MySQLInstance - Config and status values for an instance of mysqld
package MySQLInstance;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use File::Temp ();
use Data::Dumper;
$Data::Dumper::Indent = 1;

use constant MKDEBUG => $ENV{MKDEBUG};

my $option_pattern = '([^\s=]+)(?:=(\S+))?';

# SHOW GLOBAL VARIABLES dialect => mysqld --help --verbose dialect
my %alias_for = (
   ON   => 'TRUE',
   OFF  => 'FALSE',
   YES  => '1',
   NO   => '0',
);

# Many vars can have undefined values which, unless we always check,
# will cause Perl errors. Therefore, for certain vars an undefined
# value means something specific, as seen in the hash below. Otherwise,
# a blank string is used in place of an undefined value.
my %undef_for = (
   'log'                         => 'OFF',
   log_bin                       => 'OFF',
   log_slow_queries              => 'OFF',
   log_slave_updates             => 'ON',
   log_queries_not_using_indexes => 'ON',
   log_update                    => 'OFF',
   skip_bdb                      => 0,
   skip_external_locking         => 'ON',
   skip_name_resolve             => 'ON',
);

# About these sys vars the MySQL manual says: "This variable is unused."
# Or, they're simply vars we don't care about.
# They're currently only ignored in out_of_sync_sys_vars().
my %ignore_sys_var = (
   date_format     => 1,
   datetime_format => 1,
   time_format     => 1,
);

# Certain sys vars vary so much in their online vs. conf value that we
# must specially check their equality, otherwise out_of_sync_sys_vars()
# reports a number of false-positives.
# TODO: These need to be tested more thoroughly. Some will want to check
#       ON/1 as well as OFF/0, etc.
my %eq_for = (
   ft_stopword_file          => sub { return _veq(@_, '(built-in)', ''); },
   query_cache_type          => sub { return _veq(@_, 'ON', '1');        },
   ssl                       => sub { return _veq(@_, '1', 'TRUE');      },
   sql_mode                  => sub { return _veq(@_, '', 'OFF');        },

   basedir                   => sub { return _patheq(@_);                },
   language                  => sub { return _patheq(@_);                },

   log_bin                   => sub { return _eqifon(@_);                },
   log_slow_queries          => sub { return _eqifon(@_);                },

   general_log_file          => sub { return _eqifconfundef(@_);         },
   innodb_data_file_path     => sub { return _eqifconfundef(@_);         },
   innodb_log_group_home_dir => sub { return _eqifconfundef(@_);         },
   log_error                 => sub { return _eqifconfundef(@_);         },
   open_files_limit          => sub { return _eqifconfundef(@_);         },
   slow_query_log_file       => sub { return _eqifconfundef(@_);         },
   tmpdir                    => sub { return _eqifconfundef(@_);         },

   long_query_time           => sub { return _numericeq(@_);             },
);

# Certain sys vars can be given multiple times in the defaults file.
# Therefore, they are exceptions to duplicate checking.
# See http://dev.mysql.com/doc/refman/5.0/en/replication-options-slave.html
my %can_be_duplicate = (
   replicate_wild_do_table     => 1,
   replicate_wild_ignore_table => 1,
   replicate_rewrite_db        => 1,
   replicate_ignore_table      => 1,
   replicate_ignore_db         => 1,
   replicate_do_table          => 1,
   replicate_do_db             => 1,
);

# Returns an array ref of hashes. Each hash represents a single mysqld process.
# The cmd key val is suitable for passing to MySQLInstance::new().
sub mysqld_processes
{
   my ( $ps_output ) = @_;
   my @mysqld_processes;
   my $cmd = 'ps -o euser,%cpu,rss,vsz,cmd -e | grep -v grep | grep mysql';
   my $ps  = defined $ps_output ? $ps_output : `$cmd`;
   if ( $ps ) {
      MKDEBUG && _d("ps full output: $ps");
      foreach my $line ( split("\n", $ps) ) {
         MKDEBUG && _d("ps line: $line");
         my ($user, $pcpu, $rss, $vsz, $cmd) = split(/\s+/, $line, 5);
         my $bin = find_mysqld_binary_unix($cmd);
         if ( !$bin ) {
            MKDEBUG && _d('No mysqld binary in ps line');
            next;
         }
         MKDEBUG && _d("mysqld binary from ps: $bin");
         push @mysqld_processes,
            { user    => $user,
              pcpu    => $pcpu,
              rss     => $rss,
              vsz     => $vsz,
              cmd     => $cmd,
              '64bit' => `file $bin` =~ m/64-bit/ ? 'Yes' : 'No',
              syslog  => $ps =~ m/logger/ ? 'Yes' : 'No',
            };
      }
   }
   if ( MKDEBUG ) {
      my $mysqld_processes_dump = Dumper(\@mysqld_processes);
      _d("$mysqld_processes_dump");
   }
   return \@mysqld_processes;
}

sub new {
   my ( $class, $cmd ) = @_;
   my $self = {};
   MKDEBUG && _d("cmd: $cmd");
   $self->{mysqld_binary} = find_mysqld_binary_unix($cmd)
      or die "No mysqld binary found in $cmd";
   my $file_output  = `file $self->{mysqld_binary} 2>&1`;
   $self->{regsize} = get_register_size($file_output);
   %{ $self->{cmd_line_ops} }
      = map {
           my ( $var, $val ) = m/$option_pattern/o;
           $var =~ s/-/_/go;
           $val ||= $undef_for{$var} || '';
           $var => $val;
        } ($cmd =~ m/--(\S+)/g);
   $self->{cmd_line_ops}->{defaults_file} ||= '';
   $self->{conf_sys_vars}   = {};
   $self->{online_sys_vars} = {};
   if ( MKDEBUG ) {
      my $self_dump = Dumper($self);
      _d("self dump: $self_dump");
   }
   return bless $self, $class;
}

# Extracts the register size (64-bit, 32-bit, ???) from the output of 'file'.
sub get_register_size {
   my ( $file_output ) = @_;
   my ( $size ) = $file_output =~ m/\b(\d+)-bit/;
   return $size || 0;
}

sub find_mysqld_binary_unix {
   my ( $cmd ) = @_;
   my ( $binary ) = $cmd =~ m/(\S+mysqld)\b(?=\s|\Z)/;
   return $binary || '';
}

sub load_sys_vars {
   my ( $self, $dbh ) = @_;

   # This happens frequently enough in the real world to merit
   # its own perma-message that we may reuse in various places.
   my $mysqld_broken_msg
      = "The mysqld binary may be broken. "
      . "Try manually running the command above.\n"
      . "Information about system variables from the defaults file "
      . "will not be available.\n";

   # Sys vars and defaults according to mysqld (if possible; see issue 135).
   my ( $defaults_file_op, $tmp_file ) = $self->_defaults_file_op();
   my $cmd = "$self->{mysqld_binary} $defaults_file_op --help --verbose";
   MKDEBUG && _d("Getting sys vars from mysqld: $cmd");
   my $retval = system("$cmd 1>/dev/null 2>/dev/null");
   $retval = $retval >> 8;
   if ( $retval != 0 ) {
      my $self_dump = Dumper($self);
      MKDEBUG && _d("self dump: $self_dump");
      warn "Cannot execute $cmd\n" . $mysqld_broken_msg;
   }
   else {
      if ( my $mysqld_output = `$cmd` ) {
         # Parse from mysqld output the list of sys vars and their
         # default values listed at the end after all the help info.
         my ($sys_vars) = $mysqld_output =~ m/---\n(.*?)\n\n/ms;
         %{ $self->{conf_sys_vars} }
            = map {
                 my ( $var, $val ) = m/^(\S+)\s+(?:(\S+))?/;
                 $var =~ s/-/_/go;
                 if ( $val && $val =~ m/\(No/ ) { # (No default value)
                    $val = undef;
                 }
                 $val ||= $undef_for{$var} || '';
                 $var => $val;
              } split "\n", $sys_vars;

         # Parse list of default defaults files. These are the defaults
         # files that mysqld and my_print_defaults read (in order) if not
         # explicitly given a --defaults-file option. Regarding issue 58,
         # this list can have duplicates, which we must remove. Otherwise,
         # my_print_defaults will print false duplicates because it reads
         # the same file twice.
         $self->_load_default_defaults_files($mysqld_output);
      }
      else {
         warn "MySQL returned no information by running $cmd\n"
            . $mysqld_broken_msg;
      }
   }

   # Sys vars from SHOW STATUS
   $self->_load_online_sys_vars($dbh);

   # Sys vars from defaults file
   # These are used later by duplicate_values() and overriden_values().
   # These are also necessary for vars like skip-name-resolve which are not
   # shown in either SHOW VARIABLES or mysqld --help --verbose but are need
   # for checks in MySQLAdvisor. 
   $self->{defaults_files_sys_vars}
      = $self->_vars_from_defaults_file($defaults_file_op); 
   foreach my $var_val ( reverse @{ $self->{defaults_file_sys_vars} } ) {
      my ( $var, $val ) = ( $var_val->[0], $var_val->[1] );
      if ( !exists $self->{conf_sys_vars}->{$var} ) {
         $self->{conf_sys_vars}->{$var} = $val;
      }
      if ( !exists $self->{online_sys_vars}->{$var} ) {
         $self->{online_sys_vars}->{$var} = $val;
      }
   }

   return;
}

# Returns a --defaults-file cmd line op suitable for mysqld, my_print_defaults,
# etc., or a blank string if the defaults file is unknown.
sub _defaults_file_op {
   my ( $self, $ddf )   = @_;  # ddf = default defaults file (optional)
   my $defaults_file_op = '';
   my $tmp_file         = undef;
   my $defaults_file    = defined $ddf ? $ddf : $self->{cmd_line_ops}->{defaults_file};

   if ( $defaults_file && -f $defaults_file ) {
      # Copy defaults file to /tmp/ because Debian/Ubuntu mysqld apparently
      # has a bug which prevents it from being read from non-standard
      # locations.
      $tmp_file = File::Temp->new();
      my $cp_cmd = "cp $defaults_file "
                 . $tmp_file->filename;
      `$cp_cmd`;
      $defaults_file_op = "--defaults-file=" . $tmp_file->filename;

      MKDEBUG && _d(  "Tmp file for defaults file $defaults_file: "
                    . $tmp_file->filename );
   }
   else {
      MKDEBUG && _d("Defaults file does not exist: $defaults_file");
   }

   # Must return $tmp_file obj so its reference lasts into the caller because
   # when it's destroyed the actual tmp file is automatically unlinked 
   return ( $defaults_file_op, $tmp_file );
}

# Loads $self->{default_defaults_files} with the list of default defaults files
# read by mysqld, my_print_defaults, etc. with duplicates removed when no
# explicit --defaults-file option is given. Order is preserved (and important).
sub _load_default_defaults_files {
   my ( $self, $mysqld_output ) = @_;
   my ( $ddf_list ) = $mysqld_output =~ /Default options.+order:\n(.*?)\n/ms;
   if ( !$ddf_list ) {
      # TODO: change to warn and try to continue
      die "Cannot parse default defaults files: $mysqld_output\n";
   }
   MKDEBUG && _d("Parsed default defaults files: $ddf_list\n");
   my %have_seen;
   @{ $self->{default_defaults_files} }
      = grep { !$have_seen{$_}++ } split /\s/, $ddf_list;
   return;
}

# Loads $self->{default_files_sys_vars} with only the sys vars that
# are explicitly set in the defaults file. This is used for detecting
# duplicates and overriden var/vals.
sub _vars_from_defaults_file {
   my ( $self, $defaults_file_op, $my_print_defaults ) = @_;

   # Check first that my_print_defaults can be executed.
   # If not, we must die because we will not be able to do anything else.
   # TODO: change to warn and try to continue
   my $my_print_defaults_cmd = $my_print_defaults || 'my_print_defaults';
   my $retval = system("$my_print_defaults_cmd --help 1>/dev/null 2>/dev/null");
   $retval = $retval >> 8;
   if ( $retval != 0 ) {
      my $self_dump = Dumper($self);
      MKDEBUG && _d("self dump: $self_dump");
      die "Cannot execute my_print_defaults command '$my_print_defaults_cmd'";
   }

   my @defaults_file_ops;
   my @ddf_ops;

   if( !$defaults_file_op ) {
      # Having no defaults file op, my_print_defaults is going to rely
      # on the default defaults files reported by mysqld --help --verbose,
      # which we should have already saved in $self->{default_defaults_files}.
      # Due to issue 58, we must use the defaults files from our own list
      # which is free of duplicates.

      foreach my $ddf ( @{ $self->{default_defaults_files} } ) {
         my @dfo = $self->_defaults_file_op($ddf);
         if ( defined $dfo[1] ) { # tmp_file handle
            push @ddf_ops, [ @dfo ];
            push @defaults_file_ops, $dfo[0]; # defaults file op
         }
      }
   }
   else {
      $defaults_file_ops[0] = $defaults_file_op;
   }

   if ( scalar @defaults_file_ops == 0 ) {
      # This would be a rare case in which the mysqld binary was not
      # given a --defaults-file opt, and none of the default defaults
      # files parsed from mysqld --help --verbose exist.
      my $self_dump = Dumper($self);
      MKDEBUG && _d("self dump: $self_dump");
      # TODO: change to warn and try to continue
      die 'MySQL instance has no valid defaults files.'
   }

   foreach my $defaults_file_op ( @defaults_file_ops ) {
      my $cmd = "$my_print_defaults_cmd $defaults_file_op mysqld";
      MKDEBUG && _d("my_print_defaults cmd: $cmd");
      if ( my $my_print_defaults_output = `$cmd` ) {
         foreach my $var_val ( split "\n", $my_print_defaults_output ) {
            # Make sys vars from conf look like those from SHOW VARIABLES
            # (I.e. log_slow_queries instead of log-slow-queries
            # and 33554432 instead of 32M, etc.)
            my ( $var, $val ) = $var_val =~ m/^--$option_pattern/o;
            $var =~ s/-/_/go;
            # TODO: this can be more compact ( $digits_for{lc $2} )
            # and shouldn't use $1, $2
            # And I think %digits_for should go in Transformers and that
            # Transformers should be both an obj/class and simple exported
            # subs, like File::Temp, for maximal flexibility and because
            # I think it would be cool. :-)
            if ( defined $val && $val =~ /(\d+)([kKmMgGtT]?)/) {
               if ( $2 ) {
                  my %digits_for = (
                     'k'   => 1_024,
                     'K'   => 1_204,
                     'm'   => 1_048_576,
                     'M'   => 1_048_576,
                     'g'   => 1_073_741_824,
                     'G'   => 1_073_741_824,
                     't'   => 1_099_511_627_776,
                     'T'   => 1_099_511_627_776,
                  );
                  $val = $1 * $digits_for{$2};
               }
            }
            $val ||= $undef_for{$var} || '';
            push @{ $self->{defaults_file_sys_vars} }, [ $var, $val ];
         }
      }
   }
   return;
}

sub _load_online_sys_vars {
   my ( $self, $dbh ) = @_;
   %{ $self->{online_sys_vars} }
      = map { $_->{Variable_name} => $_->{Value} }
            @{ $dbh->selectall_arrayref('SHOW /*!40101 GLOBAL*/ VARIABLES',
                                        { Slice => {} })
            };
   return;
}

# Get DSN specific to this MySQL instance.  If $opts{S} is passed in, which
# corresponds to --socket on the command line, then don't convert 'localhost'
# to 127.0.0.1.
sub get_DSN {
   my ( $self, %opts ) = @_;
   my $port   = $self->{cmd_line_ops}->{port} || '';
   my $socket = $opts{S} || $self->{cmd_line_ops}->{'socket'} || '';
   my $host   = $opts{S}      ? 'localhost'
              : $port ne 3306 ? '127.0.0.1'
              :                 'localhost';
   return {
      P => $port,
      S => $socket,
      h => $host,
   };
}

# duplicate_sys_vars() returns an array ref of sys var names that
# appear more than once in the defaults file
sub duplicate_sys_vars {
   my ( $self ) = @_;
   my @duplicate_vars;
   my %have_seen;
   foreach my $var_val ( @{ $self->{defaults_file_sys_vars} } ) {
      my ( $var, $val ) = ( $var_val->[0], $var_val->[1] );
      next if $can_be_duplicate{$var};
      push @duplicate_vars, $var if $have_seen{$var}++ == 1;
   }
   return \@duplicate_vars;
}

# overriden_sys_vars() returns a hash ref of overriden sys vars:
#    key   = sys var that is overriden
#    value = array [ val being used, val overriden ]
sub overriden_sys_vars {
   my ( $self ) = @_;
   my %overriden_vars;
   foreach my $var_val ( @{ $self->{defaults_file_sys_vars} } ) {
      my ( $var, $val ) = ( $var_val->[0], $var_val->[1] );
      if ( !defined $var || !defined $val ) {
         my $dump = Dumper($var_val);
         MKDEBUG && _d("Undefined var or val: $dump");
         next;
      }
      if ( exists $self->{cmd_line_ops}->{$var} ) {
         if(    ( !defined $self->{cmd_line_ops}->{$var} && !defined $val)
             || ( $self->{cmd_line_ops}->{$var} ne $val) ) {
            $overriden_vars{$var} = [ $self->{cmd_line_ops}->{$var}, $val ];
         }
      }
   }
   return \%overriden_vars;
}

# out_of_sync_sys_vars() returns a hash ref of sys vars that differ in their
# online vs. config values:
#    {
#       out of sync sys var => {
#          online => val,
#          config => val,
#       },
#       etc.
#    }
sub out_of_sync_sys_vars {
   my ( $self ) = @_;
   my %out_of_sync_vars;

   VAR:
   foreach my $var ( keys %{ $self->{conf_sys_vars} } ) {
      next VAR if exists $ignore_sys_var{$var};
      next VAR unless exists $self->{online_sys_vars}->{$var};

      my $conf_val        = $self->{conf_sys_vars}->{$var};
      my $online_val      = $self->{online_sys_vars}->{$var};
      my $var_out_of_sync = 0;

      # TODO: try this on a server with skip_grant_tables set, it crashes on
      # me in a not-friendly way.  Probably ought to use eval {} and catch
      # error.

      # If one var has a value and that value isn't equal to the
      # other var's value, then they're out of sync. However, if
      # both vars are valueless (0, '0', or ''), then they are
      # in sync--this prevents 0 and '' being treated as out of sync.
      if ( ($conf_val || $online_val) && ($conf_val ne $online_val) ) {
         $var_out_of_sync = 1;

         # Try some exceptions, cases like where ON and TRUE are the
         # same to us but not to Perl.
         if ( exists $eq_for{$var} ) {
            # If they're equal then they're not (!) out of sync
            $var_out_of_sync = !$eq_for{$var}->($conf_val, $online_val);
         }
         if ( exists $alias_for{$online_val} ) {
            $var_out_of_sync = 0 if $conf_val eq $alias_for{$online_val};
         }
      }

      if ( $var_out_of_sync ) {
         $out_of_sync_vars{$var} = { online=>$online_val, config=>$conf_val };
      }
   }

   return \%out_of_sync_vars;
}

sub load_status_vals {
   my ( $self, $dbh ) = @_;
   %{ $self->{status_vals} }
      = map { $_->{Variable_name} => $_->{Value} }
            @{ $dbh->selectall_arrayref('SHOW /*!50002 GLOBAL */ STATUS',
                                        { Slice => {} })
            };
   return;
}

sub get_eq_for {
   my ( $var ) = @_;
   if ( exists $eq_for{$var} ) {
      return $eq_for{$var};
   }
   return;
}

# variable eq: returns true if x and y equal each other
# where x and y can be either val1 or val2.
sub _veq { 
   my ( $x, $y, $val1, $val2 ) = @_;
   return 1 if ( ($x eq $val1 || $x eq $val2) && ($y eq $val1 || $y eq $val2) );
   return 0;
}

# path eq: returns true if x and y are directory paths that differ
# only by a trailing /.
sub _patheq {
   my ( $x, $y ) = @_;
   $x .= '/' if $x !~ m/\/$/;
   $y .= '/' if $y !~ m/\/$/;
   return $x eq $y;
}

# eq if ON: returns true if either x or y is ON and the other value
# is any value.
sub _eqifon { 
   my ( $x, $y ) = @_;
   return 1 if ( $x && $x eq 'ON' && $y );
   return 1 if ( $y && $y eq 'ON' && $x );
   return 0;
}

# eq if config value is undefined (''): returns true if the config value
# is undefined because for certain vars and undefined conf val results
# in the online value showing the built-in default val. These vals, then,
# are not technically out-of-sync.
sub _eqifconfundef {
   my ( $conf_val, $online_val ) = @_;
   return ($conf_val eq '' ? 1 : 0);
}

# numeric eq: returns true if the two vals are numerically eq. A string
# eq test works for most cases, even numbers, except when decimal precision
# becomes an issue. long_query_time, for example, can be set to 2.2 in the
# config file, but the online value shows its full precision as 2.200000.
# Thus, a string eq incorrectly fails.
sub _numericeq {
   my ( $x, $y ) = @_;
   return ($x == $y ? 1 : 0);
}

sub _d {
   my ( $line ) = (caller(0))[2];
   print "# MySQLInstance:$line $PID ", @_, "\n";
}

1;

# ###########################################################################
# End MySQLInstance package
# ###########################################################################
