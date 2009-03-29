# This program is copyright 2009 Percona Inc.
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
# DuplicateKeyFinder package $Revision$
# ###########################################################################
package DuplicateKeyFinder;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use List::Util qw(min);

use constant MKDEBUG => $ENV{MKDEBUG};

sub new {
   my ( $class ) = @_;
   my $self = {
      # These are used in case you want to look back and see more
      # details about what happened inside get_duplicate_keys().
      keys        => undef,  # copy of last keys that we worked on
      unique_cols => undef,  # unique cols for those last keys (hashref)
      unique_sets => undef,  # unique sets for those last keys (arrayref) 
   };
   return bless $self, $class;
}

# %args should contain:
#
#  *  keys           (req) A hashref from TableParser::get_keys().
#  *  tbl_info       (req) { db, tbl, engine, ddl } hashref.
#  *  callback       (req) An anonymous subroutine, called for each dupe found.
#  *  ignore_order   Order never matters for any type of index (generally order
#                    matters except for FULLTEXT).
#  *  ignore_type    Compare indexes of different types as if they're the same.
#  *  clustered      Perform duplication checks against the clustered  key.
#
# Returns an arrayref of duplicate key hashrefs.  Each contains
#
#  *  key               The name of the index that's a duplicate.
#  *  cols              The columns in that key (arrayref).
#  *  duplicate_of      The name of the index it duplicates.
#  *  duplicate_of_cols The columns of the index it duplicates.
#  *  reason            A human-readable description of why this is a duplicate.
sub get_duplicate_keys {
   my ( $self, %args ) = @_;
   die "I need a keys argument" unless $args{keys};
   my %all_keys  = %{$args{keys}}; # copy keys because we change stuff
   $self->{keys} = \%all_keys;
   my $primary_key;
   my @unique_keys;
   my @normal_keys;
   my @fulltext_keys;
   my %pass_args = %args;
   delete $pass_args{keys};

   ALL_KEYS:
   foreach my $key ( values %all_keys ) {
      $key->{real_cols} = $key->{colnames}; 
      $key->{len_cols}  = length $key->{colnames};

      # The PRIMARY KEY is treated specially. It is effectively never a
      # duplicate, so it is never removed. It is compared to all other
      # keys, and in any case of duplication, the PRIMARY is always kept
      # and the other key removed.
      if ( $key->{name} eq 'PRIMARY' ) {
         $primary_key = $key;
         next ALL_KEYS;
      }

      my $is_fulltext = $key->{type} eq 'FULLTEXT' ? 1 : 0;

      # Key column order matters for all keys except FULLTEXT, so we only
      # sort if --ignoreorder or FULLTEXT. 
      if ( $args{ignore_order} || $is_fulltext  ) {
         my $ordered_cols = join(',', sort(split(/,/, $key->{colnames})));
         MKDEBUG && _d('Reordered', $key->{name}, 'cols from',
            $key->{colnames}, 'to', $ordered_cols); 
         $key->{colnames} = $ordered_cols;
      }

      # By default --allstruct is false, so keys of different structs
      # (BTREE, HASH, FULLTEXT, SPATIAL) are kept and compared separately.
      # UNIQUE keys are also separated just to make comparisons easier.
      my $push_to = $key->{is_unique} ? \@unique_keys : \@normal_keys;
      if ( !$args{ignore_type} ) {
         $push_to = \@fulltext_keys if $is_fulltext;
         # TODO:
         # $push_to = \@hash_keys     if $is_hash;
         # $push_to = \@spatial_keys  if $is_spatial;
      }
      push @$push_to, $key; 
   }

   my @dupes;

   MKDEBUG && _d('Start unconstraining redundantly unique keys');
   # See http://code.google.com/p/maatkit/wiki/DeterminingDuplicateKeys
   # First, determine which unique keys define unique columns and which
   # define unique sets.
   my %unique_cols;
   my @unique_sets;
   my %unconstrain;   # unique keys to unconstrain
   UNIQUE_KEY:
   foreach my $unique_key ( $primary_key, @unique_keys ) {
      next unless $unique_key; # primary key may be undefined
      my $cols = $unique_key->{cols};
      if ( @$cols == 1 ) {
         MKDEBUG && _d($unique_key->{name},'defines unique column:',$cols->[0]);
         # Save only the first unique key for the unique col. If there
         # are others, then they are exact duplicates and will be removed
         # later when unique keys are compared to unique keys.
         if ( !exists $unique_cols{$cols->[0]} ) {
            $unique_cols{$cols->[0]}  = $unique_key;
            $unique_key->{unique_col} = 1;
         }
      }
      else {
         local $LIST_SEPARATOR = '-';
         MKDEBUG && _d($unique_key->{name}, 'defines unique set:', @$cols);
         push @unique_sets, { cols => $cols, key => $unique_key };
      }
   }

   # Second, find which unique sets can be unconstraind (i.e. those
   # which have which have at least one unique column).
   UNIQUE_SET:
   foreach my $unique_set ( @unique_sets ) {
      my $n_unique_cols = 0;
      COL:
      foreach my $col ( @{$unique_set->{cols}} ) {
         if ( exists $unique_cols{$col} ) {
            MKDEBUG && _d('Unique set', $unique_set->{key}->{name},
               'has unique col', $col);
            last COL if ++$n_unique_cols > 1;
            $unique_set->{constraining_key} = $unique_cols{$col};
         }
      }
      if ( $n_unique_cols && $unique_set->{key}->{name} ne 'PRIMARY' ) {
         # Unique set is redundantly constrained.
         MKDEBUG && _d('Will unconstrain unique set',
            $unique_set->{key}->{name},
            'because it is redundantly constrained by key',
            $unique_set->{constraining_key}->{name},
            '(',$unique_set->{constraining_key}->{colnames},')');
         $unconstrain{$unique_set->{key}->{name}}
            = $unique_set->{constraining_key};
      }
   }

   # And finally, unconstrain the redudantly unique sets found above by
   # removing them from the list of unique keys and adding them to the
   # list of normal keys.
   for my $i ( 0..$#unique_keys ) {
      if ( exists $unconstrain{$unique_keys[$i]->{name}} ) {
         MKDEBUG && _d('Normalizing', $unique_keys[$i]->{name});
         $unique_keys[$i]->{unconstrained} = 1;
         $unique_keys[$i]->{constraining_key}
            = $unconstrain{$unique_keys[$i]->{name}};
         push @normal_keys, $unique_keys[$i];
         delete $unique_keys[$i];
      }
   }
   $self->{unique_cols} = \%unique_cols;
   $self->{unique_sets} = \@unique_sets;
   MKDEBUG && _d('No more keys');

   # If you're tempted to check the primary key against uniques before
   # unconstraining redundantly unique keys: don't. In cases like
   #    PRIMARY KEY (a, b)
   #    UNIQUE KEY  (a)
   # the unique key will be wrongly removed. It is needed to keep
   # column a unique. The process of unconstraining redundantly unique
   # keys marks single column unique keys so that they are never removed
   # (the mark is adding unique_col=>1 to the unique key's hash).
   if ( $primary_key ) {
      MKDEBUG && _d('Start comparing PRIMARY KEY to UNIQUE keys');
      $self->remove_prefix_duplicates(
            keys           => [$primary_key],
            remove_keys    => \@unique_keys,
            duplicate_keys => \@dupes,
            %pass_args);

      MKDEBUG && _d('Start comparing PRIMARY KEY to normal keys');
      $self->remove_prefix_duplicates(
            keys           => [$primary_key],
            remove_keys    => \@normal_keys,
            duplicate_keys => \@dupes,
            %pass_args);
   }

   MKDEBUG && _d('Start comparing UNIQUE keys to normal keys');
   $self->remove_prefix_duplicates(
         keys           => \@unique_keys,
         remove_keys    => \@normal_keys,
         duplicate_keys => \@dupes,
         %pass_args);

   MKDEBUG && _d('Start comparing normal keys');
   $self->remove_prefix_duplicates(
         keys           => \@normal_keys,
         duplicate_keys => \@dupes,
         %pass_args);

   # If --allstruct, then these special struct keys (FULLTEXT, HASH, etc.)
   # will have already been put in and handled by @normal_keys.
   MKDEBUG && _d('Start comparing FULLTEXT keys');
   $self->remove_prefix_duplicates(
         keys             => \@fulltext_keys,
         exact_duplicates => 1,
         %pass_args);

   # TODO: other structs

   # For engines with a clustered index, if a key ends with a prefix
   # of the primary key, it's a duplicate. Example:
   #    PRIMARY KEY (a)
   #    KEY foo (b, a)
   # Key foo is redundant to PRIMARY.
   if ( $primary_key
        && $args{clustered}
        && $args{tbl_info}->{engine} =~ m/^(?:InnoDB|solidDB)$/ ) {

      MKDEBUG && _d('Start removing UNIQUE dupes of clustered key');
      $self->remove_clustered_duplicates(
            primary_key => $primary_key,
            keys        => \@unique_keys,
            %pass_args);

      MKDEBUG && _d('Start removing ordinary dupes of clustered key');
      $self->remove_clustered_duplicates(
            primary_key => $primary_key,
            keys        => \@normal_keys,
            %pass_args);
   }

   return \@dupes;
}

sub get_duplicate_fks {
   my ( $self, %args ) = @_;
   die "I need a keys argument" unless $args{keys};
   my @fks = values %{$args{keys}};
   my @dupes;
   foreach my $i ( 0..$#fks - 1 ) {
      next unless $fks[$i];
      foreach my $j ( $i+1..$#fks ) {
         next unless $fks[$j];
         # A foreign key is a duplicate no matter what order the
         # columns are in, so re-order them alphabetically so they
         # can be compared.
         my $i_cols  = join(',', sort(split(/,/, $fks[$i]->{colnames})));
         my $j_cols  = join(',', sort(split(/,/, $fks[$j]->{colnames})));
         my $i_pcols = join(',', sort(split(/,/, $fks[$i]->{parent_colnames})));
         my $j_pcols = join(',', sort(split(/,/, $fks[$j]->{parent_colnames})));

         if ( $fks[$i]->{parent_tbl} eq $fks[$j]->{parent_tbl}
              && $i_cols  eq $j_cols
              && $i_pcols eq $j_pcols ) {
            my $dupe = {
               key               => $fks[$j]->{name},
               cols              => $fks[$j]->{colnames},
               duplicate_of      => $fks[$i]->{name},
               duplicate_of_cols => $fks[$i]->{colnames},
               reason       =>
                    "FOREIGN KEY $fks[$j]->{name} ($fks[$j]->{colnames}) "
                  . "REFERENCES $fks[$j]->{parent_tbl} "
                  . "($fks[$j]->{parent_colnames}) "
                  . 'is a duplicate of '
                  . "FOREIGN KEY $fks[$i]->{name} ($fks[$i]->{colnames}) "
                  . "REFERENCES $fks[$i]->{parent_tbl} "
                  ."($fks[$i]->{parent_colnames})"
            };
            push @dupes, $dupe;
            delete $fks[$j];
            $args{callback}->($dupe, %args) if $args{callback};
         }
      }
   }
   return \@dupes;
}

# TODO: Document this subroutine.
# %args should contain the same things passed to get_duplicate_keys(), plus:
#  *  remove_keys       ????
#  *  duplicate_keys    ????
#  *  exact_duplicates  ????
sub remove_prefix_duplicates {
   my ( $self, %args ) = @_;
   my $keys;
   my $remove_keys;
   my @dupes;
   my $keep_index;
   my $remove_index;
   my $last_key;
   my $remove_key_offset;

   $keys  = $args{keys};
   @$keys = sort { $a->{colnames} cmp $b->{colnames} }
            grep { defined $_; }
            @$keys;

   if ( $args{remove_keys} ) {
      $remove_keys  = $args{remove_keys};
      @$remove_keys = sort { $a->{colnames} cmp $b->{colnames} }
                      grep { defined $_; }
                      @$remove_keys;

      $remove_index      = 1;
      $keep_index        = 0;
      $last_key          = scalar(@$keys) - 1;
      $remove_key_offset = 0;
   }
   else {
      $remove_keys       = $keys;
      $remove_index      = 0;
      $keep_index        = 1;
      $last_key          = scalar(@$keys) - 2;
      $remove_key_offset = 1;
   }
   my $last_remove_key = scalar(@$remove_keys) - 1;

   I_KEY:
   foreach my $i ( 0..$last_key ) {
      next I_KEY unless defined $keys->[$i];

      J_KEY:
      foreach my $j ( $i+$remove_key_offset..$last_remove_key ) {
         next J_KEY unless defined $remove_keys->[$j];

         my $keep = ($i, $j)[$keep_index];
         my $rm   = ($i, $j)[$remove_index];

         my $keep_name     = $keys->[$keep]->{name};
         my $keep_cols     = $keys->[$keep]->{colnames};
         my $keep_len_cols = $keys->[$keep]->{len_cols};
         my $rm_name       = $remove_keys->[$rm]->{name};
         my $rm_cols       = $remove_keys->[$rm]->{colnames};
         my $rm_len_cols   = $remove_keys->[$rm]->{len_cols};

         MKDEBUG && _d('Comparing [keep]', $keep_name, '(',$keep_cols,')',
            'to [remove if dupe]', $rm_name, '(',$rm_cols,')');

         # Compare the whole remove key to the keep key, not just
         # the their common minimum length prefix. This is correct
         # because it enables magick that I should document. :-)
         if (    substr($rm_cols, 0, $rm_len_cols)
              eq substr($keep_cols, 0, $rm_len_cols) ) {

            # FULLTEXT keys, for example, are only duplicates if they
            # are exact duplicates.
            if ( $args{exact_duplicates} && ($rm_len_cols < $keep_len_cols) ) {
               MKDEBUG && _d($rm_name, 'not exact duplicate of', $keep_name);
               next J_KEY;
            }

            # Do not remove the unique key that is constraining a single
            # column to uniqueness. This prevents UNIQUE KEY (a) from being
            # removed by PRIMARY KEY (a, b).
            if ( exists $remove_keys->[$rm]->{unique_col} ) {
               MKDEBUG && _d('Cannot remove', $rm_name,
                  'because is constrains col',
                  $remove_keys->[$rm]->{cols}->[0]);
               next J_KEY;
            }

            MKDEBUG && _d('Remove', $remove_keys->[$rm]->{name});
            my $reason;
            if ( $remove_keys->[$rm]->{unconstrained} ) {
               $reason .= "Uniqueness of $rm_name ignored because "
                        . $remove_keys->[$rm]->{constraining_key}->{name}
                        . " is a stronger constraint\n"; 
            }
            $reason .= $rm_name
                     . ($rm_len_cols < $keep_len_cols ? ' is a left-prefix of '
                                                      : ' is a duplicate of ')
                     . $keep_name;
            my $dupe = {
               key               => $rm_name,
               cols              => $remove_keys->[$rm]->{real_cols},
               duplicate_of      => $keep_name,
               duplicate_of_cols => $keys->[$keep]->{real_cols},
               reason            => $reason,
            };
            push @dupes, $dupe;
            delete $remove_keys->[$rm];

            $args{callback}->($dupe, %args) if $args{callback};

            next I_KEY if $remove_index == 0;
            next J_KEY if $remove_index == 1;
         }
         else {
            MKDEBUG && _d($rm_name, 'not left-prefix of', $keep_name);
            next I_KEY;
         }
      }
   }
   MKDEBUG && _d('No more keys');

   @$keys        = grep { defined $_; } @$keys;
   @$remove_keys = grep { defined $_; } @$remove_keys if $args{remove_keys};
   push @{$args{duplicate_keys}}, @dupes if $args{duplice_keys};

   return;
}

sub remove_clustered_duplicates {
   my ( $self, %args ) = @_;
   die "I need a primary_key argument" unless $args{primary_key};
   die "I need a keys argument"        unless $args{keys};
   my $pkcols = $args{primary_key}->{colnames};
   my $keys   = $args{keys};
   my @dupes;
   # TODO: this can be done more easily now that each key has
   # its cols in an array, so we just have to look at cols[-1].
   KEY:
   for my $i ( 0 .. @$keys - 1 ) {
      my $suffix = $keys->[$i]->{colnames};
      SUFFIX:
      while ( $suffix =~ s/`[^`]+`,// ) {
         my $len = min(length($pkcols), length($suffix));
         if ( substr($suffix, 0, $len) eq substr($pkcols, 0, $len) ) {
            my $dupe = {
               key               => $keys->[$i]->{name},
               cols              => $keys->[$i]->{real_cols},
               duplicate_of      => $args{primary_key}->{name},
               duplicate_of_cols => $args{primary_key}->{real_cols},
               reason            => "Key $keys->[$i]->{name} "
                                    . "ends with a prefix of the clustered "
                                    . "index",
            };
            push @dupes, $dupe;
            delete $keys->[$i];
            $args{callback}->($dupe, %args) if $args{callback};
            last SUFFIX;
         }
      }
   }
   MKDEBUG && _d('No more keys');

   @$keys = grep { defined $_; } @$keys;
   push @{$args{duplicate_keys}}, @dupes if $args{duplice_keys};

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
# End DuplicateKeyFinder package
# ###########################################################################
