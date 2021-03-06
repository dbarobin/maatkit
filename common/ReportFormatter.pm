# This program is copyright 2009-2011 Percona Inc.
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
# ReportFormatter package $Revision$
# ###########################################################################
package ReportFormatter;

# Package: ReportFormatter
# ReportFormatter makes columnized reports given variable-width data lines.
# It does the hard work of automatically sizing columns and truncating data
# to fit the line width (unless all data fits the line which doesn't happen
# often).  This involves the following magic.
#
# Internally, all column widths are *first* treated as percentages of the
# line width. Even if a column is specified with width=>N where N is some
# length of characters, this is converted to a percent/line width (rounded up).
# 
# Columns specified with width=>N or width_pct=>P (where P is some percent
# of *total* line width, not remaining line width when used with other width=>N
# columns) are fixed.  You get exactly what you specify even if this results
# in the column header/name or values being truncated to fit.  Otherwise,
# the column is "auto-width" and you get whatever the package gives you.
#
# add_line() keeps track of min and max column values.  When get_report() is
# called, it calls _calculate_column_widths() which begins the magic.  It
# converts each column's percentage width to characters, called the print width.
# So width_pct=>50 == print_width=>39 (characters).  If the column is fixed
# (i.e. *not* auto-width) then print width is fixed.  Otherwise, the print
# width is adjusted as follows.
#
# The print width is set to the min val if, for some reason, it's less than
# the min val.  This is so the column is at least wide enough to print the
# minimum value.  Else, if there's a max val and the print val is wider than
# it, then the print val is set to the max val.  This reclaims "extra space"
# from auto-width cols.
#
# Extra space is distributed evenly among auto-width cols with print widths
# less than the column's max val or header/name.  This widens auto-width cols
# to either show longer values or truncate the column header/name less.
# 
# After these adjustments, get_report() calls _truncate_headers() and
# _truncate_line_values().  These truncate output to the columns' final,
# calculated widths.

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use List::Util qw(min max);
use POSIX qw(ceil);

eval { require Term::ReadKey };
my $have_term = $EVAL_ERROR ? 0 : 1;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Arguments:
#  * underline_header     bool: underline headers with =
#  * line_prefix          scalar: prefix every line with this string
#  * line_width           scalar: line width in characters or 'auto'
#  * column_spacing       scalar: string between columns (default one space)
#  * extend_right         bool: allow right-most column to extend beyond
#                               line width (default: no)
#  * column_errors        scalar: die or warn on column errors (default warn)
#  * truncate_header_side scalar: left or right (default left)
#  * strip_whitespace     bool: strip leading and trailing whitespace
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      underline_header     => 1,
      line_prefix          => '# ',
      line_width           => 78,
      column_spacing       => ' ',
      extend_right         => 0,
      truncate_line_mark   => '...',
      column_errors        => 'warn',
      truncate_header_side => 'left',
      strip_whitespace     => 1,
      %args,              # args above can be overriden, args below cannot
      n_cols              => 0,
   };

   # This is not tested or currently used, but I like the idea and
   # think one day it will be very handy in mk-config-diff.
   if ( ($self->{line_width} || '') eq 'auto' ) {
      die "Cannot auto-detect line width because the Term::ReadKey module "
         . "is not installed" unless $have_term;
      ($self->{line_width}) = GetTerminalSize();
   }
   MKDEBUG && _d('Line width:', $self->{line_width});

   return bless $self, $class;
}

sub set_title {
   my ( $self, $title ) = @_;
   $self->{title} = $title;
   return;
}

# @cols is an array of hashrefs.  Each hashref describes a column and can
# have the following keys:
# Required args:
#   * name           column's name
# Optional args:
#   * width              fixed column width in characters
#   * width_pct          relative column width as percentage of line width
#   * truncate           can truncate column (default yes)
#   * truncate_mark      append string to truncate col vals (default ...)
#   * truncate_side      truncate left or right side of value (default right)
#   * undef_value        string for undef values (default '')
sub set_columns {
   my ( $self, @cols ) = @_;
   my $min_hdr_wid = 0;  # check that header fits on line
   my $used_width  = 0;
   my @auto_width_cols;

   for my $i ( 0..$#cols ) {
      my $col      = $cols[$i];
      my $col_name = $col->{name};
      my $col_len  = length $col_name;
      die "Column does not have a name" unless defined $col_name;

      if ( $col->{width} ) {
         $col->{width_pct} = ceil(($col->{width} * 100) / $self->{line_width});
         MKDEBUG && _d('col:', $col_name, 'width:', $col->{width}, 'chars =',
            $col->{width_pct}, '%');
      }

      if ( $col->{width_pct} ) {
         $used_width += $col->{width_pct};
      }
      else {
         # Auto-width columns get an equal share of whatever amount
         # of line width remains.  Later, they can be adjusted again.
         MKDEBUG && _d('Auto width col:', $col_name);
         $col->{auto_width} = 1;
         push @auto_width_cols, $i;
      }

      # Set defaults if another value wasn't given.
      $col->{truncate}        = 1 unless defined $col->{truncate};
      $col->{truncate_mark}   = '...' unless defined $col->{truncate_mark};
      $col->{truncate_side} ||= 'right';
      $col->{undef_value}     = '' unless defined $col->{undef_value};

      # These values will be computed/updated as lines are added.
      $col->{min_val} = 0;
      $col->{max_val} = 0;

      # Calculate if the minimum possible header width will exceed the line.
      $min_hdr_wid        += $col_len;
      $col->{header_width} = $col_len;

      # Used with extend_right.
      $col->{right_most} = 1 if $i == $#cols;

      push @{$self->{cols}}, $col;
   }

   $self->{n_cols} = scalar @cols;

   if ( ($used_width || 0) > 100 ) {
      die "Total width_pct for all columns is >100%";
   }

   # Divide remain line width (in %) among auto-width columns.
   if ( @auto_width_cols ) {
      my $wid_per_col = int((100 - $used_width) / scalar @auto_width_cols);
      MKDEBUG && _d('Line width left:', (100-$used_width), '%;',
         'each auto width col:', $wid_per_col, '%');
      map { $self->{cols}->[$_]->{width_pct} = $wid_per_col } @auto_width_cols;
   }

   # Add to the minimum possible header width the spacing between columns.
   $min_hdr_wid += ($self->{n_cols} - 1) * length $self->{column_spacing};
   MKDEBUG && _d('min header width:', $min_hdr_wid);
   if ( $min_hdr_wid > $self->{line_width} ) {
      MKDEBUG && _d('Will truncate headers because min header width',
         $min_hdr_wid, '> line width', $self->{line_width});
      $self->{truncate_headers} = 1;
   }

   return;
}

# Add a line to the report.  Does not print the line or the report.
# @vals is an array of values for each column.  There should be as
# many vals as columns.  Use undef for columns that have no values.
sub add_line {
   my ( $self, @vals ) = @_;
   my $n_vals = scalar @vals;
   if ( $n_vals != $self->{n_cols} ) {
      $self->_column_error("Number of values $n_vals does not match "
         . "number of columns $self->{n_cols}");
   }
   for my $i ( 0..($n_vals-1) ) {
      my $col   = $self->{cols}->[$i];
      my $val   = defined $vals[$i] ? $vals[$i] : $col->{undef_value};
      if ( $self->{strip_whitespace} ) {
         $val =~ s/^\s+//g;
         $val =~ s/\s+$//;
         $vals[$i] = $val;
      }
      my $width = length $val;
      $col->{min_val} = min($width, ($col->{min_val} || $width));
      $col->{max_val} = max($width, ($col->{max_val} || $width));
   }
   push @{$self->{lines}}, \@vals;
   return;
}

# Returns the formatted report for the columns and lines added earlier.
sub get_report {
   my ( $self, %args ) = @_;

   $self->_calculate_column_widths();
   $self->_truncate_headers() if $self->{truncate_headers};
   $self->_truncate_line_values(%args);

   my @col_fmts = $self->_make_column_formats();
   my $fmt      = ($self->{line_prefix} || '')
                . join($self->{column_spacing}, @col_fmts);
   MKDEBUG && _d('Format:', $fmt);

   # Make the printf line format for the header and ensure that its labels
   # are always left justified.
   (my $hdr_fmt = $fmt) =~ s/%([^-])/%-$1/g;

   # Build the report line by line, starting with the title and header lines.
   my @lines;
   push @lines, sprintf "$self->{line_prefix}$self->{title}" if $self->{title};
   push @lines, $self->_truncate_line(
         sprintf($hdr_fmt, map { $_->{name} } @{$self->{cols}}),
         strip => 1,
         mark  => '',
   );

   if ( $self->{underline_header} ) {
      my @underlines = map { '=' x $_->{print_width} } @{$self->{cols}};
      push @lines, $self->_truncate_line(
         sprintf($fmt, @underlines),
         mark  => '',
      );
   }

   push @lines, map {
      my $vals = $_;
      my $i    = 0;
      my @vals = map {
            defined $_ ? $_ : $self->{cols}->[$i++]->{undef_value}
      } @$vals;
      my $line = sprintf($fmt, @vals);
      if ( $self->{extend_right} ) {
         $line;
      }
      else {
         $self->_truncate_line($line);
      }
   } @{$self->{lines}};

   return join("\n", @lines) . "\n";
}

sub truncate_value {
   my ( $self, $col, $val, $width, $side ) = @_;
   return $val if length $val <= $width;
   return $val if $col->{right_most} && $self->{extend_right};
   $side  ||= $col->{truncate_side};
   my $mark = $col->{truncate_mark};
   if ( $side eq 'right' ) {
      $val  = substr($val, 0, $width - length $mark);
      $val .= $mark;
   }
   elsif ( $side eq 'left') {
      $val = $mark . substr($val, -1 * $width + length $mark);
   }
   else {
      MKDEBUG && _d("I don't know how to", $side, "truncate values");
   }
   return $val;
}

sub _calculate_column_widths {
   my ( $self ) = @_;

   my $extra_space = 0;
   foreach my $col ( @{$self->{cols}} ) {
      my $print_width = int($self->{line_width} * ($col->{width_pct} / 100));

      MKDEBUG && _d('col:', $col->{name}, 'width pct:', $col->{width_pct},
         'char width:', $print_width,
         'min val:', $col->{min_val}, 'max val:', $col->{max_val});

      if ( $col->{auto_width} ) {
         if ( $col->{min_val} && $print_width < $col->{min_val} ) {
            MKDEBUG && _d('Increased to min val width:', $col->{min_val});
            $print_width = $col->{min_val};
         }
         elsif ( $col->{max_val} &&  $print_width > $col->{max_val} ) {
            MKDEBUG && _d('Reduced to max val width:', $col->{max_val});
            $extra_space += $print_width - $col->{max_val};
            $print_width  = $col->{max_val};
         }
      }

      $col->{print_width} = $print_width;
      MKDEBUG && _d('print width:', $col->{print_width});
   }

   MKDEBUG && _d('Extra space:', $extra_space);
   while ( $extra_space-- ) {
      foreach my $col ( @{$self->{cols}} ) {
         if (    $col->{auto_width}
              && (    $col->{print_width} < $col->{max_val}
                   || $col->{print_width} < $col->{header_width})
         ) {
            # MKDEBUG && _d('Increased', $col->{name}, 'width');
            $col->{print_width}++;
         }
      }
   }

   return;
}

sub _truncate_headers {
   my ( $self, $col ) = @_;
   my $side = $self->{truncate_header_side};
   foreach my $col ( @{$self->{cols}} ) {
      my $col_name    = $col->{name};
      my $print_width = $col->{print_width};
      next if length $col_name <= $print_width;
      $col->{name}  = $self->truncate_value($col, $col_name, $print_width, $side);
      MKDEBUG && _d('Truncated hdr', $col_name, 'to', $col->{name},
         'max width:', $print_width);
   }
   return;
}

sub _truncate_line_values {
   my ( $self, %args ) = @_;
   my $n_vals = $self->{n_cols} - 1;
   foreach my $vals ( @{$self->{lines}} ) {
      for my $i ( 0..$n_vals ) {
         my $col   = $self->{cols}->[$i];
         my $val   = defined $vals->[$i] ? $vals->[$i] : $col->{undef_value};
         my $width = length $val;

         if ( $col->{print_width} && $width > $col->{print_width} ) {
            if ( !$col->{truncate} ) {
               $self->_column_error("Value '$val' is too wide for column "
                  . $col->{name});
            }

            # If _column_error() dies then we never get here.  If it warns
            # then we truncate the value despite $col->{truncate} being
            # false so the user gets something rather than nothing.
            my $callback    = $args{truncate_callback};
            my $print_width = $col->{print_width};
            $val = $callback ? $callback->($col, $val, $print_width)
                 :             $self->truncate_value($col, $val, $print_width);
            MKDEBUG && _d('Truncated val', $vals->[$i], 'to', $val,
               '; max width:', $print_width);
            $vals->[$i] = $val;
         }
      }
   }
   return;
}

# Make the printf line format for each row given the columns' settings.
sub _make_column_formats {
   my ( $self ) = @_;
   my @col_fmts;
   my $n_cols = $self->{n_cols} - 1;
   for my $i ( 0..$n_cols ) {
      my $col = $self->{cols}->[$i];

      # Normally right-most col has no width so it can potentially
      # extend_right.  But if it's right-justified, it requires a width.
      my $width = $col->{right_most} && !$col->{right_justify} ? ''
                : $col->{print_width};

      my $col_fmt  = '%' . ($col->{right_justify} ? '' : '-') . $width . 's';
      push @col_fmts, $col_fmt;
   }
   return @col_fmts;
}

sub _truncate_line {
   my ( $self, $line, %args ) = @_;
   my $mark = defined $args{mark} ? $args{mark} : $self->{truncate_line_mark};
   if ( $line ) {
      $line =~ s/\s+$// if $args{strip};
      my $len  = length($line);
      if ( $len > $self->{line_width} ) {
         $line  = substr($line, 0, $self->{line_width} - length $mark);
         $line .= $mark if $mark;
      }
   }
   return $line;
}

sub _column_error {
   my ( $self, $err ) = @_;
   my $msg = "Column error: $err";
   $self->{column_errors} eq 'die' ? die $msg : warn $msg;
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
# End ReportFormatter package
# ###########################################################################
