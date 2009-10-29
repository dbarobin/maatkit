# This program is copyright 2007-2009 Baron Schwartz.
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
# QueryRewriter package $Revision$
# ###########################################################################
use strict;
use warnings FATAL => 'all';

package QueryRewriter;

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG};

# A list of verbs that can appear in queries.  I know this is incomplete -- it
# does not have CREATE, DROP, ALTER, TRUNCATE for example.  But I don't need
# those for my client yet.  Other verbs: KILL, LOCK, UNLOCK
our $verbs   = qr{^SHOW|^FLUSH|^COMMIT|^ROLLBACK|^BEGIN|SELECT|INSERT
                  |UPDATE|DELETE|REPLACE|^SET|UNION|^START|^LOCK}xi;
my $quote_re = qr/"(?:(?!(?<!\\)").)*"|'(?:(?!(?<!\\)').)*'/; # Costly!
my $bal;
$bal         = qr/
                  \(
                  (?:
                     (?> [^()]+ )    # Non-parens without backtracking
                     |
                     (??{ $bal })    # Group with matching parens
                  )*
                  \)
                 /x;

# The one-line comment pattern is quite crude.  This is intentional for
# performance.  The multi-line pattern does not match version-comments.
my $olc_re = qr/(?:--|#)[^'"\r\n]*(?=[\r\n]|\Z)/;  # One-line comments
my $mlc_re = qr#/\*[^!].*?\*/#sm;                  # But not /*!version */

sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   return bless $self, $class;
}

# Strips comments out of queries.
sub strip_comments {
   my ( $self, $query ) = @_;
   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   return $query;
}

# Shortens long queries by normalizing stuff out of them.  $length is used only
# for IN() lists.
sub shorten {
   my ( $self, $query, $length ) = @_;
   # Shorten multi-value insert/replace, all the way up to on duplicate key
   # update if it exists.
   $query =~ s{
      \A(
         (?:INSERT|REPLACE)
         (?:\s+LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)?
         (?:\s\w+)*\s+\S+\s+VALUES\s*\(.*?\)
      )
      \s*,\s*\(.*?(ON\s+DUPLICATE|\Z)}
      {$1 /*... omitted ...*/$2}xsi;

   # Shortcut!  Find out if there's an IN() list with values.
   return $query unless $query =~ m/IN\s*\(\s*(?!select)/i;

   # Shorten long IN() lists of literals.  But only if the string is longer than
   # the $length limit.  Assumption: values don't contain commas or closing
   # parens inside them.  Assumption: all values are the same length.
   if ( $length && length($query) > $length ) {
      my ($left, $mid, $right) = $query =~ m{
         (\A.*?\bIN\s*\()     # Everything up to the opening of IN list
         ([^\)]+)             # Contents of the list
         (\).*\Z)             # The rest of the query
      }xsi;
      if ( $left ) {
         # Compute how many to keep and try to get rid of the middle of the
         # list until it's short enough.
         my $targ = $length - length($left) - length($right);
         my @vals = split(/,/, $mid);
         my @left = shift @vals;
         my @right;
         my $len  = length($left[0]);
         while ( @vals && $len < $targ / 2 ) {
            $len += length($vals[0]) + 1;
            push @left, shift @vals;
         }
         while ( @vals && $len < $targ ) {
            $len += length($vals[-1]) + 1;
            unshift @right, pop @vals;
         }
         $query = $left . join(',', @left)
                . (@right ? ',' : '')
                . " /*... omitted " . scalar(@vals) . " items ...*/ "
                . join(',', @right) . $right;
      }
   }

   return $query;
}

# Normalizes variable queries to a "query fingerprint" by abstracting away
# parameters, canonicalizing whitespace, etc.  See
# http://dev.mysql.com/doc/refman/5.0/en/literals.html for literal syntax.
# Note: Any changes to this function must be profiled for speed!  Speed of this
# function is critical for mk-log-parser.  There are known bugs in this, but the
# balance between maybe-you-get-a-bug and speed favors speed.  See past
# revisions of this subroutine for more correct, but slower, regexes.
sub fingerprint {
   my ( $self, $query ) = @_;

   # First, we start with a bunch of special cases that we can optimize because
   # they are special behavior or because they are really big and we want to
   # throw them away as early as possible.
   $query =~ m#\ASELECT /\*!40001 SQL_NO_CACHE \*/ \* FROM `# # mysqldump query
      && return 'mysqldump';
   # Matches queries like REPLACE /*foo.bar:3/3*/ INTO checksum.checksum
   $query =~ m#/\*\w+\.\w+:[0-9]/[0-9]\*/#     # mk-table-checksum, etc query
      && return 'maatkit';
   # Administrator commands appear to be a comment, so return them as-is
   $query =~ m/\A# administrator command: /
      && return $query;
   # Special-case for stored procedures.
   $query =~ m/\A\s*(call\s+\S+)\(/i
      && return lc($1); # Warning! $1 used, be careful.
   # mysqldump's INSERT statements will have long values() lists, don't waste
   # time on them... they also tend to segfault Perl on some machines when you
   # get to the "# Collapse IN() and VALUES() lists" regex below!
   if ( my ($beginning) = $query =~ m/\A((?:INSERT|REPLACE)(?: IGNORE)? INTO .+? VALUES \(.*?\)),\(/i ) {
      $query = $beginning; # Shorten multi-value INSERT statements ASAP
   }

   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   $query =~ s/\Ause \S+\Z/use ?/i       # Abstract the DB in USE
      && return $query;

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings
   # This regex is extremely broad in its definition of what looks like a
   # number.  That is for speed.
   $query =~ s/[0-9+-][0-9a-f.xb+-]*/?/g;# Anything vaguely resembling numbers
   $query =~ s/[xb.+-]\?/?/g;            # Clean up leftovers
   $query =~ s/\A\s+//;                  # Chop off leading whitespace
   chomp $query;                         # Kill trailing whitespace
   $query =~ tr[ \n\t\r\f][ ]s;          # Collapse whitespace
   $query = lc $query;
   $query =~ s/\bnull\b/?/g;             # Get rid of NULLs
   $query =~ s{                          # Collapse IN and VALUES lists
               \b(in|values?)(?:[\s,]*\([\s?,]*\))+
              }
              {$1(?+)}gx;
   $query =~ s{                          # Collapse UNION
               \b(select\s.*?)(?:(\sunion(?:\sall)?)\s\1)+
              }
              {$1 /*repeat$2*/}xg;
   $query =~ s/\blimit \?(?:, ?\?| offset \?)?/limit ?/; # LIMIT
   # The following are disabled because of speed issues.  Should we try to
   # normalize whitespace between and around operators?  My gut feeling is no.
   # $query =~ s/ , | ,|, /,/g;    # Normalize commas
   # $query =~ s/ = | =|= /=/g;       # Normalize equals
   # $query =~ s# [,=+*/-] ?|[,=+*/-] #+#g;    # Normalize operators
   return $query;
}

sub _distill_verbs {
   my ( $self, $query ) = @_;

   # Special cases.
   $query =~ m/\A\s*call\s+(\S+)\(/i
      && return "CALL $1"; # Warning! $1 used, be careful.
   $query =~ m/\A# administrator/
      && return "ADMIN";
   $query =~ m/\A\s*use\s+/
      && return "USE";
   $query =~ m/\A\s*UNLOCK TABLES/i
      && return "UNLOCK";

   # More special cases for data defintion statements.
   # The two evals are a hack to keep Perl from warning that
   # "QueryParser::data_def_stmts" used only once: possible typo at...".
   # Some day we'll group all our common regex together in a packet and
   # export/import them properly.
   eval $QueryParser::data_def_stmts;
   eval $QueryParser::tbl_ident;
   my ( $dds ) = $query =~ /^\s*($QueryParser::data_def_stmts)\b/i;
   if ( $dds ) {
      my ( $obj ) = $query =~ m/$dds.+(DATABASE|TABLE)\b/i;
      $obj = uc $obj if $obj;
      MKDEBUG && _d('Data def statment:', $dds, 'obj:', $obj);
      my ($db_or_tbl)
         = $query =~ m/(?:TABLE|DATABASE)\s+($QueryParser::tbl_ident)(\s+.*)?/i;
      MKDEBUG && _d('Matches db or table:', $db_or_tbl);
      return uc($dds . ($obj ? " $obj" : '')), $db_or_tbl;
   }

   # First, get the query type -- just extract all the verbs and collapse them
   # together.
   my @verbs = $query =~ m/\b($verbs)\b/gio;
   @verbs    = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } map { uc } @verbs;
   };
   my $verbs = join(q{ }, @verbs);
   $verbs =~ s/( UNION SELECT)+/ UNION/g;

   return $verbs;
}

sub _distill_tables {
   my ( $self, $query, $table, %args ) = @_;
   my $qp = $args{qp} || $self->{QueryParser};
   die "I need a qp argument" unless $qp;

   # "Fingerprint" the tables.
   my @tables = map {
      $_ =~ s/`//g;
      $_ =~ s/(_?)[0-9]+/$1?/g;
      $_;
   } $qp->get_tables($query);

   push @tables, $table if $table;

   # Collapse the table list
   @tables = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } @tables;
   };

   return @tables;
}

# This is kind of like fingerprinting, but it super-fingerprints to something
# that shows the query type and the tables/objects it accesses.
sub distill {
   my ( $self, $query, %args ) = @_;

   # _distill_verbs() may return a table if it's a special statement
   # like TRUNCATE TABLE foo.  _distill_tables() handles some but not
   # all special statements so we pass it this special table in case
   # it's a statement it can't handle.  If it can handle it, it will
   # eliminate any duplicate tables.
   my ($verbs, $table)  = $self->_distill_verbs($query, %args);
   my @tables           = $self->_distill_tables($query, $table, %args);
   $query               = join(q{ }, $verbs, @tables);
   return $query;
}

sub convert_to_select {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s{
                 \A.*?
                 update\s+(.*?)
                 \s+set\b(.*?)
                 (?:\s*where\b(.*?))?
                 (limit\s*[0-9]+(?:\s*,\s*[0-9]+)?)?
                 \Z
              }
              {__update_to_select($1, $2, $3, $4)}exsi
      || $query =~ s{
                    \A.*?
                    (?:insert|replace)\s+
                    .*?\binto\b(.*?)\(([^\)]+)\)\s*
                    values?\s*(\(.*?\))\s*
                    (?:\blimit\b|on\s*duplicate\s*key.*)?\s*
                    \Z
                 }
                 {__insert_to_select($1, $2, $3)}exsi
      || $query =~ s{
                    \A.*?
                    delete\s+(.*?)
                    \bfrom\b(.*)
                    \Z
                 }
                 {__delete_to_select($1, $2)}exsi;
   $query =~ s/\s*on\s+duplicate\s+key\s+update.*\Z//si;
   $query =~ s/\A.*?(?=\bSELECT\s*\b)//ism;
   return $query;
}

sub convert_select_list {
   my ( $self, $query ) = @_;
   $query =~ s{
               \A\s*select(.*?)\bfrom\b
              }
              {$1 =~ m/\*/ ? "select 1 from" : "select isnull(coalesce($1)) from"}exi;
   return $query;
}

sub __delete_to_select {
   my ( $delete, $join ) = @_;
   if ( $join =~ m/\bjoin\b/ ) {
      return "select 1 from $join";
   }
   return "select * from $join";
}

sub __insert_to_select {
   my ( $tbl, $cols, $vals ) = @_;
   MKDEBUG && _d('Args:', @_);
   my @cols = split(/,/, $cols);
   MKDEBUG && _d('Cols:', @cols);
   $vals =~ s/^\(|\)$//g; # Strip leading/trailing parens
   my @vals = $vals =~ m/($quote_re|[^,]*${bal}[^,]*|[^,]+)/g;
   MKDEBUG && _d('Vals:', @vals);
   if ( @cols == @vals ) {
      return "select * from $tbl where "
         . join(' and ', map { "$cols[$_]=$vals[$_]" } (0..$#cols));
   }
   else {
      return "select * from $tbl limit 1";
   }
}

sub __update_to_select {
   my ( $from, $set, $where, $limit ) = @_;
   return "select $set from $from "
      . ( $where ? "where $where" : '' )
      . ( $limit ? " $limit "      : '' );
}

sub wrap_in_derived {
   my ( $self, $query ) = @_;
   return unless $query;
   return $query =~ m/\A\s*select/i
      ? "select 1 from ($query) as x limit 1"
      : $query;
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
# End QueryRewriter package
# ###########################################################################
