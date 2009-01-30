# This program is copyright 2007-@CURRENTYEAR@ Baron Schwartz.
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
# TableParser package $Revision$
# ###########################################################################
package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use List::Util qw(min);

use constant MKDEBUG => $ENV{MKDEBUG};

sub new {
   my ( $class ) = @_;
   return bless {}, $class;
}

# Several subs in this module require either a $ddl or $tbl param.
#
# $ddl is the return value from MySQLDump::get_create_table() (which returns
# the output of SHOW CREATE TALBE).
#
# $tbl is the return value from the sub below, parse().
#
# And some subs have an optional $opts param which is a hashref of options.
# $opts{mysql_version} is typically used, which is the return value from
# VersionParser::parser() (which returns a zero-padded MySQL version,
# e.g. 004001000 for 4.1.0).

sub parse {
   my ( $self, $ddl, $opts ) = @_;

   if ( ref $ddl eq 'ARRAY' ) {
      if ( lc $ddl->[0] eq 'table' ) {
         $ddl = $ddl->[1];
      }
      else {
         return {
            engine => 'VIEW',
         };
      }
   }

   if ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "Cannot parse table definition; is ANSI quoting "
         . "enabled or SQL_QUOTE_SHOW_CREATE disabled?";
   }

   # Lowercase identifiers to avoid issues with case-sensitivity in Perl.
   # (Bug #1910276).
   $ddl =~ s/(`[^`]+`)/\L$1/g;

   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   MKDEBUG && _d('Storage engine: ', $engine);

   my @defs = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols = map { $_ =~ m/`([^`]+)`/g } @defs;
   MKDEBUG && _d('Columns: ' . join(', ', @cols));

   # Save the column definitions *exactly*
   my %def_for;
   @def_for{@cols} = @defs;

   # Find column types, whether numeric, whether nullable, whether
   # auto-increment.
   my (@nums, @null);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};
      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   my %keys;
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      # Make allowances for HASH bugs in SHOW CREATE TABLE.  A non-MEMORY table
      # will report its index as USING HASH even when this is not supported.
      # The true type should be BTREE.  See
      # http://bugs.mysql.com/bug.php?id=22632
      if ( $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      # Determine index type
      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      if ( $opts->{mysql_version} && $opts->{mysql_version} lt '004001000'
         && $engine =~ m/HEAP|MEMORY/i )
      {
         $type = 'HASH'; # MySQL pre-4.1 supports only HASH indexes on HEAP
      }

      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( split(',', $cols) ) {
         # Parse columns of index including potential column prefixes
         # E.g.: `a`,`b`(20)
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;
      MKDEBUG && _d("Index $name columns: " . join(', ', @cols));

      $keys{$name} = {
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         unique       => $unique,
         is_col       => { map { $_ => 1 } @cols },
         is_nullable  => scalar(grep { $is_nullable{$_} } @cols),
         type         => $type,
         name         => $name,
      };
   }

   return {
      cols           => \@cols,
      col_posn       => { map { $cols[$_] => $_ } 0..$#cols },
      is_col         => { map { $_ => 1 } @cols },
      null_cols      => \@null,
      is_nullable    => \%is_nullable,
      is_autoinc     => \%is_autoinc,
      keys           => \%keys,
      defs           => \%def_for,
      numeric_cols   => \@nums,
      is_numeric     => \%is_numeric,
      engine         => $engine,
      type_for       => \%type_for,
   };
}

# Sorts indexes in this order: PRIMARY, unique, non-nullable, any (shortest
# first, alphabetical).  Only BTREE indexes are considered.
# TODO: consider length as # of bytes instead of # of columns.
sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{unique} <=> !$tbl->{keys}->{$b}->{unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   MKDEBUG && _d('Indexes sorted best-first: ' . join(', ', @indexes));
   return @indexes;
}

# Finds the 'best' index; if the user specifies one, dies if it's not in the
# table.
sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         # The user specified an index, so we can't choose our own.
         die "Index '$index' does not exist in table";
      }
      else {
         # Try to pick the best index.
         # TODO: eliminate indexes that have column prefixes.
         ($best) = $self->sort_indexes($tbl);
      }
   }
   MKDEBUG && _d("Best index found is " . ($best || 'undef'));
   return $best;
}

# Takes a dbh, database, table, quoter, and WHERE clause, and reports the
# indexes MySQL thinks are best for EXPLAIN SELECT * FROM that table.  If no
# WHERE, just returns an empty list.  If no possible_keys, returns empty list,
# even if 'key' is not null.  Only adds 'key' to the list if it's included in
# possible_keys.
sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   # Normalize columns to lowercase
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      MKDEBUG && _d("possible_keys=$expl->{possible_keys}");
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         MKDEBUG && _d("MySQL chose $expl->{key}");
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         MKDEBUG && _d('Before deduping: ' . join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      MKDEBUG && _d('Final list: ' . join(', ', @candidates));
      return @candidates;
   }
   else {
      MKDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub table_exists {
   my ( $self, $dbh, $db, $tbl, $q, $can_insert ) = @_;
   my $db_tbl = $q->quote($db, $tbl);
   my $sql    = $can_insert ? "REPLACE INTO $db_tbl " : '';
   $sql      .= "SELECT * FROM $db_tbl LIMIT 0";
   MKDEBUG && _d("table_exists check for $db_tbl: $sql");
   eval { $dbh->do($sql); };
   MKDEBUG && _d("eval error (if any): $EVAL_ERROR");
   return 0 if $EVAL_ERROR;
   return 1;
}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\) (?:ENGINE|TYPE)=(\w+)/;
   return $engine || undef;
}

# The general format of a key is
# [FOREIGN|UNIQUE|PRIMARY|FULLTEXT|SPATIAL] KEY `name` [USING BTREE|HASH] (`cols`).
sub get_keys {
   my ( $self, $ddl, $opts ) = @_;

   # Find and filter the indexes.
   my @indexes =
      grep { $_ !~ m/FOREIGN/ }
      $ddl =~ m/((?:\w+ )?KEY .+\))/mg;

   # Make allowances for HASH bugs in SHOW CREATE TABLE.  A non-MEMORY table
   # will report its index as USING HASH even when this is not supported.  The
   # true type should be BTREE.  See http://bugs.mysql.com/bug.php?id=22632
   my $engine = $self->get_engine($ddl);
   if ( $engine !~ m/MEMORY|HEAP/ ) {
      @indexes = map { $_ =~ s/USING HASH/USING BTREE/; $_; } @indexes;
   }

   my @keys = map {
      my ( $unique, $struct, $cols )
         = $_ =~ m/(?:(\w+) )?KEY.+(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $_ =~ m/(FULLTEXT|SPATIAL)/;
      $struct = $struct || $special || 'BTREE';
      my ( $name ) = $_ =~ m/KEY `(.*?)` \(/;

      # MySQL pre-4.1 supports only HASH indexes.
      if ( $opts->{version} lt '004001000' && $engine =~ m/HEAP|MEMORY/i ) {
         $struct = 'HASH';
      }

      {
         struct   => $struct,
         cols     => $cols,
         name     => $name || 'PRIMARY',
         unique   => $unique && $unique =~ m/(UNIQUE|PRIMARY)/ ? 1 : 0,
      }
   } @indexes;

   return \@keys;
}

sub get_fks {
   my ( $self, $ddl, $opts ) = @_;

   my @fks = $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg;

   my @result = map {
      my ( $name ) = $_ =~ m/CONSTRAINT `(.*?)`/;
      my ( $fkcols ) = $_ =~ m/\(([^\)]+)\)/;
      my ( $cols )   = $_ =~ m/REFERENCES.*?\(([^\)]+)\)/;
      my ( $parent ) = $_ =~ m/REFERENCES (\S+) /;
      if ( $parent !~ m/\./ ) {
         $parent = "`$opts->{database}`.$parent";
      }
      {  name   => $name,
         parent => $parent,
         cols   => $cols,
         fkcols => $fkcols,
      };
   } @fks;
   return \@result;
}

sub _remove_duplicate_left_prefixes {
   my ( $preferred_keys, $secondary_keys, %args ) = @_;
   return unless $preferred_keys;
   my @dupes;
   my ($rm_from, $keep_in);
   my ($rm_key, $keep_key);
   my ($last_i, $j_offset);

   my $i_keys = [];
   @$i_keys   = sort { $a->{cols} cmp $b->{cols} }
                     grep { defined $_; }
                     @$preferred_keys;

   my $j_keys;
   if ( $secondary_keys ) {
      # If secondary keys are given, then the preferred keys
      # really are preferred, so we remove secondary keys.
      @$j_keys  = sort { $a->{cols} cmp $b->{cols} }
                  grep { defined $_; }
                  @$secondary_keys;
      $rm_key   = 1; # secondary (j keys)
      $keep_key = 0; # preferred (i keys)
      $rm_from  = $j_keys;
      $keep_in  = $i_keys;
      $last_i   = scalar @$i_keys - 1;
      $j_offset = 0;
   }
   else {
      # If secondary keys are not given, then the preferred and
      # secondary keys are really the same list of keys, so we
      # remove i keys;
      $j_keys   = $i_keys;
      $rm_key   = 0; # i keys
      $keep_key = 1; # j keys
      $rm_from  = $i_keys;
      $keep_in  = $j_keys;
      $last_i   = scalar @$i_keys - 2;
      $j_offset = 1;
   }
   my $n_j_keys = scalar @$j_keys - 1;

   I_KEY:
   foreach my $i ( 0..$last_i ) {
      next I_KEY unless defined $i_keys->[$i];

      J_KEY:
      foreach my $j ( $i+$j_offset..$n_j_keys ) {
         next KEY_J unless defined $j_keys->[$j];

         my $keep = ($i, $j)[$keep_key];
         my $rm   = ($i, $j)[$rm_key];

         my $keep_name     = $keep_in->[$keep]->{name};
         my $keep_cols     = $keep_in->[$keep]->{cols};
         my $keep_len_cols = $keep_in->[$keep]->{len_cols};
         my $rm_name       = $rm_from->[$rm]->{name};
         my $rm_cols       = $rm_from->[$rm]->{cols};
         my $rm_len_cols   = $rm_from->[$rm]->{len_cols};

         MKDEBUG && _d("Comparing [keep] $keep_name ($keep_cols) "
            . "to [remove if dupe] $rm_name ($rm_cols)");

         if (    substr($rm_cols, 0, $rm_len_cols)
              eq substr($keep_cols, 0, $rm_len_cols) ) {

            # FULLTEXT keys, for example, are only duplicates if they
            # are exact duplicates.
            if ( $args{exact_duplicates} && ($rm_len_cols < $keep_len_cols) ) {
               MKDEBUG && _d("$rm_name not exact duplicate of $keep_name");
               next J_KEY;
            }

            MKDEBUG && _d("Remove $rm_from->[$rm]->{name}");
            my $reason = "$rm_from->[$rm]->{name} "
                       . "($rm_from->[$rm]->{cols}) is a "
                       . ($rm_len_cols < $keep_len_cols ? 'left-prefix of '
                                                        : 'duplicate of ')
                       . "$keep_in->[$keep]->{name} "
                       . "($keep_in->[$keep]->{cols})";
            push @dupes,
               {
                  key          => $rm_name,
                  duplicate_of => $keep_name,
                  reason       => $reason,
               };
            delete $rm_from->[$rm];
            next I_KEY if $rm_key == $i;
            next J_KEY if $rm_key == $j;
         }
         else {
            MKDEBUG && _d("$rm_name not left-prefix of $keep_name");
            next I_KEY;
         }
      }
   }
   MKDEBUG && _d('No more keys');
   @$i_keys = grep { defined $_; } @$i_keys;
   @$j_keys = grep { defined $_; } @$j_keys if $secondary_keys;
   return ($i_keys, $j_keys, \@dupes);
}

sub get_duplicate_keys {
   my ( $self, $all_keys, $opts ) = @_;
   my $primary_key;
   my @unique_keys;
   my @keys;
   my @fulltext_keys;

   ALL_KEYS:
   foreach my $key ( @$all_keys ) {
      $key->{len_cols} = length $key->{cols};

      # The PRIMARY KEY is treated specially. It is effectively never a
      # duplicate, so it is never removed. It is compared to all other
      # keys, and in any case of duplication, the PRIMARY is always kept
      # and the other key removed.
      if ( $key->{name} eq 'PRIMARY' ) {
         $primary_key = $key;
         next ALL_KEYS;
      }

      my $is_fulltext = $key->{struct} eq 'FULLTEXT' ? 1 : 0;

      # Key column order matters for all keys except FULLTEXT, so we only
      # sort if --ignoreorder or FULLTEXT.
      if ( $opts->{ignore_order} || $is_fulltext  ) {
         my $ordered_cols = join(',', sort(split(/,/, $key->{cols})));
         MKDEBUG && _d("Reordered $key->{name} cols "
            . "from ($key->{cols}) to ($ordered_cols)");
         $key->{cols} = $ordered_cols;
      }

      # By default --allstruct is false, so keys of different structs
      # (BTREE, HASH, FULLTEXT, SPATIAL) are kept and compared separately.
      # UNIQUE keys are also separated just to make comparisons easier.
      my $push_to = $key->{unique} ? \@unique_keys : \@keys;
      if ( !$opts->{ignore_type} ) {
         $push_to = \@fulltext_keys if $is_fulltext;
         # TODO:
         # $push_to = \@hash_keys     if $is_hash;
         # $push_to = \@spatial_keys  if $is_spatial;
      }
      push @$push_to, $key; 
   }

   my $good_keys;
   my $dupe_keys;
   my @dupes;

   if ( $primary_key ) {
      MKDEBUG && _d('Start comparing PRIMARY KEY to UNIQUE keys');
      (undef, $good_keys, $dupe_keys)
         = _remove_duplicate_left_prefixes([$primary_key], \@unique_keys);
      push @dupes, @$dupe_keys;
      @unique_keys = @$good_keys;

      MKDEBUG && _d('Start comparing PRIMARY KEY to regular keys');
      (undef, $good_keys, $dupe_keys)
         = _remove_duplicate_left_prefixes([$primary_key], \@keys);
      push @dupes, @$dupe_keys;
      @keys = @$good_keys;
   }

   MKDEBUG && _d('Start comparing UNIQUE keys');
   ($good_keys, undef, $dupe_keys)
      = _remove_duplicate_left_prefixes(\@unique_keys);
   push @dupes, @$dupe_keys;
   @unique_keys= @$good_keys;

   MKDEBUG && _d('Start comparing regular keys');
   ($good_keys, undef, $dupe_keys)
      = _remove_duplicate_left_prefixes(\@keys);
   push @dupes, @$dupe_keys;
   @keys = @$good_keys;

   MKDEBUG && _d('Start comparing UNIQUE keys to regular keys');
   (undef, $good_keys, $dupe_keys)
      = _remove_duplicate_left_prefixes(\@unique_keys, \@keys);
   push @dupes, @$dupe_keys;
   @keys = @$good_keys;

   # If --allstruct, then these special struct keys (FULLTEXT, HASH, etc.)
   # will have already been put in and handled by @keys.
   MKDEBUG && _d('Start comparing FULLTEXT keys');
   ($good_keys, undef, $dupe_keys)
      = _remove_duplicate_left_prefixes(\@fulltext_keys, undef,
            exact_duplicates => 1);
   push @dupes, @$dupe_keys;
   @fulltext_keys = @$good_keys;

   # TODO: other structs
   return \@dupes;


   # TODO: update code below
   my @result;
   my %seen;
   # If the key ends with a prefix of the primary key, it's a duplicate.
   if ( $opts->{clustered} && $opts->{engine} =~ m/^(?:InnoDB|solidDB)$/ ) {
      my $i = 0;
      my $found = 0;
      while ( $i < @keys ) {
         if ( $keys[$i]->{name} eq 'PRIMARY' ) {
            $found = 1;
            last;
         }
         $i++;
      }
      if ( $found ) {
         my $pkcols = $keys[$i]->{cols};
         KEY:
         foreach my $j ( 0..$#keys ) {
            next KEY if $i == $j;
            my $suffix = $keys[$j]->{cols};
            SUFFIX:
            while ( $suffix =~ s/`[^`]+`,// ) {
               my $len = min(length($pkcols), length($suffix));
               if ( (($keys[$i]->{struct} eq $keys[$j]->{struct}) || $opts->{ignore_type})
                  && substr($suffix, 0, $len) eq substr($pkcols, 0, $len))
               {
                  push @result, $keys[$i] unless $seen{$i}++;
                  push @result, $keys[$j] unless $seen{$j}++;
                  last SUFFIX;
               }
            }
         }
      }
   }

}

sub get_duplicate_fks {
   my ( $self, $fks, $opts ) = @_;
   my @fks = @$fks;
   my %seen; # Avoid outputting a fk more than once.
   my @result;
   foreach my $i ( 0..$#fks - 1 ) {
      foreach my $j ( $i+1..$#fks ) {
         # A foreign key is a duplicate no matter what order the columns are in, so
         # re-order them alphabetically so they can be compared.
         my $i_cols = join(', ', map { "`$_`" } sort($fks[$i]->{cols} =~ m/`([^`]+)`/g));
         my $j_cols = join(', ', map { "`$_`" } sort($fks[$j]->{cols} =~ m/`([^`]+)`/g));
         my $i_fkcols = join(', ', map { "`$_`" } sort($fks[$i]->{fkcols} =~ m/`([^`]+)`/g));
         my $j_fkcols = join(', ', map { "`$_`" } sort($fks[$j]->{fkcols} =~ m/`([^`]+)`/g));
         if ( $fks[$i]->{parent} eq $fks[$j]->{parent}
               && $i_cols eq $j_cols
               && $i_fkcols eq $j_fkcols
         ) {
            push @result, $fks[$i] unless $seen{$i}++;
            push @result, $fks[$j] unless $seen{$j}++;
         }
      }
   }

   return \@result;
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
# End TableParser package
# ###########################################################################
