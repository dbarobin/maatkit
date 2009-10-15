#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 34;

require "../TableParser.pm";
require "../Quoter.pm";
require '../DSNParser.pm';
require '../Sandbox.pm';
my $dp  = new DSNParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $q   = new Quoter();
my $tp  = new TableParser(Quoter=>$q);
my $tbl;

sub throws_ok {
   my ( $code, $pat, $msg ) = @_;
   eval { $code->(); };
   like( $EVAL_ERROR, $pat, $msg );
}

sub load_file {
   my ($file) = @_;
   open my $fh, "<", $file or die $!;
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   return $contents;
}

eval {
   $tp->parse( load_file('samples/noquotes.sql') );
};
like($EVAL_ERROR, qr/quoting/, 'No quoting');

eval {
   $tp->parse( load_file('samples/ansi_quotes.sql') );
};
like($EVAL_ERROR, qr/quoting/, 'ANSI quoting');

$tbl = $tp->parse( load_file('samples/t1.sql') );
is_deeply(
   $tbl,
   {  cols         => [qw(a)],
      col_posn     => { a => 0 },
      is_col       => { a => 1 },
      is_autoinc   => { a => 0 },
      null_cols    => [qw(a)],
      is_nullable  => { a => 1 },
      clustered_key => undef,
      keys         => {},
      defs         => { a => '  `a` int(11) default NULL' },
      numeric_cols => [qw(a)],
      is_numeric   => { a => 1 },
      engine       => 'MyISAM',
      type_for     => { a => 'int' },
   },
   'Basic table is OK',
);

$tbl = $tp->parse( load_file('samples/TableParser-prefix_idx.sql') );
is_deeply(
   $tbl,
   {
      cols           => [ 'a', 'b' ],
      col_posn       => { a => 0, b => 1 },
      is_col         => { a => 1, b => 1 },
      is_autoinc     => { 'a' => 0, 'b' => 0 },
      null_cols      => [ 'a', 'b' ],
      is_nullable    => { 'a' => 1, 'b' => 1 },
      clustered_key  => undef,
      keys           => {
         prefix_idx => {
            is_unique => 0,
            is_col => {
               a => 1,
               b => 1,
            },
            name => 'prefix_idx',
            type => 'BTREE',
            is_nullable => 2,
            colnames => '`a`(10),`b`(20)',
            cols => [ 'a', 'b' ],
            col_prefixes => [ 10, 20 ],
         },
         mix_idx => {
            is_unique => 0,
            is_col => {
               a => 1,
               b => 1,
            },
            name => 'mix_idx',
            type => 'BTREE',
            is_nullable => 2,
            colnames => '`a`,`b`(20)',
            cols => [ 'a', 'b' ],
            col_prefixes => [ undef, 20 ],
         },
      },
      defs           => {
         a => '  `a` varchar(64) default NULL',
         b => '  `b` varchar(64) default NULL'
      },
      numeric_cols   => [],
      is_numeric     => {},
      engine         => 'MyISAM',
      type_for       => { a => 'varchar', b => 'varchar' },
   },
   'Indexes with prefixes parse OK (fixes issue 1)'
);

$tbl = $tp->parse( load_file('samples/sakila.film.sql') );
is_deeply(
   $tbl,
   {  cols => [
         qw(film_id title description release_year language_id
            original_language_id rental_duration rental_rate
            length replacement_cost rating special_features
            last_update)
      ],
      col_posn => {
         film_id              => 0,
         title                => 1,
         description          => 2,
         release_year         => 3,
         language_id          => 4,
         original_language_id => 5,
         rental_duration      => 6,
         rental_rate          => 7,
         length               => 8,
         replacement_cost     => 9,
         rating               => 10,
         special_features     => 11,
         last_update          => 12,
      },
      is_autoinc => {
         film_id              => 1,
         title                => 0,
         description          => 0,
         release_year         => 0,
         language_id          => 0,
         original_language_id => 0,
         rental_duration      => 0,
         rental_rate          => 0,
         length               => 0,
         replacement_cost     => 0,
         rating               => 0,
         special_features     => 0,
         last_update          => 0,
      },
      is_col => {
         film_id              => 1,
         title                => 1,
         description          => 1,
         release_year         => 1,
         language_id          => 1,
         original_language_id => 1,
         rental_duration      => 1,
         rental_rate          => 1,
         length               => 1,
         replacement_cost     => 1,
         rating               => 1,
         special_features     => 1,
         last_update          => 1,
      },
      null_cols   => [qw(description release_year original_language_id length rating special_features )],
      is_nullable => {
         description          => 1,
         release_year         => 1,
         original_language_id => 1,
         length               => 1,
         special_features     => 1,
         rating               => 1,
      },
      clustered_key => 'PRIMARY',
      keys => {
         PRIMARY => {
            colnames     => '`film_id`',
            cols         => [qw(film_id)],
            col_prefixes => [undef],
            is_col       => { film_id => 1 },
            is_nullable  => 0,
            is_unique    => 1,
            type         => 'BTREE',
            name         => 'PRIMARY',
         },
         idx_title => {
            colnames     => '`title`',
            cols         => [qw(title)],
            col_prefixes => [undef],
            is_col       => { title => 1, },
            is_nullable  => 0,
            is_unique    => 0,
            type         => 'BTREE',
            name         => 'idx_title',
         },
         idx_fk_language_id => {
            colnames     => '`language_id`',
            cols         => [qw(language_id)],
            col_prefixes => [undef],
            is_unique    => 0,
            is_col       => { language_id => 1 },
            is_nullable  => 0,
            type         => 'BTREE',
            name         => 'idx_fk_language_id',
         },
         idx_fk_original_language_id => {
            colnames     => '`original_language_id`',
            cols         => [qw(original_language_id)],
            col_prefixes => [undef],
            is_unique    => 0,
            is_col       => { original_language_id => 1 },
            is_nullable  => 1,
            type         => 'BTREE',
            name         => 'idx_fk_original_language_id',
         },
      },
      defs => {
         film_id      => "  `film_id` smallint(5) unsigned NOT NULL auto_increment",
         title        => "  `title` varchar(255) NOT NULL",
         description  => "  `description` text",
         release_year => "  `release_year` year(4) default NULL",
         language_id  => "  `language_id` tinyint(3) unsigned NOT NULL",
         original_language_id =>
            "  `original_language_id` tinyint(3) unsigned default NULL",
         rental_duration =>
            "  `rental_duration` tinyint(3) unsigned NOT NULL default '3'",
         rental_rate      => "  `rental_rate` decimal(4,2) NOT NULL default '4.99'",
         length           => "  `length` smallint(5) unsigned default NULL",
         replacement_cost => "  `replacement_cost` decimal(5,2) NOT NULL default '19.99'",
         rating           => "  `rating` enum('G','PG','PG-13','R','NC-17') default 'G'",
         special_features =>
            "  `special_features` set('Trailers','Commentaries','Deleted Scenes','Behind the Scenes') default NULL",
         last_update =>
            "  `last_update` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP",
      },
      numeric_cols => [
         qw(film_id release_year language_id original_language_id rental_duration
            rental_rate length replacement_cost)
      ],
      is_numeric => {
         film_id              => 1,
         release_year         => 1,
         language_id          => 1,
         original_language_id => 1,
         rental_duration      => 1,
         rental_rate          => 1,
         length               => 1,
         replacement_cost     => 1,
      },
      engine   => 'InnoDB',
      type_for => {
         film_id              => 'smallint',
         title                => 'varchar',
         description          => 'text',
         release_year         => 'year',
         language_id          => 'tinyint',
         original_language_id => 'tinyint',
         rental_duration      => 'tinyint',
         rental_rate          => 'decimal',
         length               => 'smallint',
         replacement_cost     => 'decimal',
         rating               => 'enum',
         special_features     => 'set',
         last_update          => 'timestamp',
      },
   },
   'sakila.film',
);

is_deeply(
   [$tp->sort_indexes($tbl)],
   [qw(PRIMARY idx_fk_language_id idx_title idx_fk_original_language_id)],
   'Sorted indexes OK'
);

is($tp->find_best_index($tbl), 'PRIMARY', 'Primary key is best');
is($tp->find_best_index($tbl, 'idx_title'), 'idx_title', 'Specified key is best');
throws_ok (
   sub { $tp->find_best_index($tbl, 'foo') },
   qr/does not exist/,
   'Index does not exist',
);

$tbl = $tp->parse( load_file('samples/temporary_table.sql') );
is_deeply(
   $tbl,
   {  cols         => [qw(a)],
      col_posn     => { a => 0 },
      is_col       => { a => 1 },
      is_autoinc   => { a => 0 },
      null_cols    => [qw(a)],
      is_nullable  => { a => 1 },
      clustered_key => undef,
      keys         => {},
      defs         => { a => '  `a` int(11) default NULL' },
      numeric_cols => [qw(a)],
      is_numeric   => { a => 1 },
      engine       => 'MyISAM',
      type_for     => { a => 'int' },
   },
   'Temporary table',
);

$tbl = $tp->parse( load_file('samples/hyphentest.sql') );
is_deeply(
   $tbl,
   {  'is_autoinc' => {
         'sort_order'                => 0,
         'pfk-source_instrument_id'  => 0,
         'pfk-related_instrument_id' => 0
      },
      'null_cols'    => [],
      'numeric_cols' => [
         'pfk-source_instrument_id', 'pfk-related_instrument_id',
         'sort_order'
      ],
      'cols' => [
         'pfk-source_instrument_id', 'pfk-related_instrument_id',
         'sort_order'
      ],
      'col_posn' => {
         'sort_order'                => 2,
         'pfk-source_instrument_id'  => 0,
         'pfk-related_instrument_id' => 1
      },
      clustered_key => 'PRIMARY',
      'keys' => {
         'sort_order' => {
            'is_unique'    => 0,
            'is_col'       => { 'sort_order' => 1 },
            'name'         => 'sort_order',
            'type'         => 'BTREE',
            'col_prefixes' => [ undef ],
            'is_nullable'  => 0,
            'colnames'     => '`sort_order`',
            'cols'         => [ 'sort_order' ]
         },
         'PRIMARY' => {
            'is_unique' => 1,
            'is_col' => {
               'pfk-source_instrument_id'  => 1,
               'pfk-related_instrument_id' => 1
            },
            'name'         => 'PRIMARY',
            'type'         => 'BTREE',
            'col_prefixes' => [ undef, undef ],
            'is_nullable'  => 0,
            'colnames' =>
               '`pfk-source_instrument_id`,`pfk-related_instrument_id`',
            'cols' =>
               [ 'pfk-source_instrument_id', 'pfk-related_instrument_id' ]
         }
      },
      'defs' => {
         'sort_order' => '  `sort_order` int(11) NOT NULL',
         'pfk-source_instrument_id' =>
            '  `pfk-source_instrument_id` int(10) unsigned NOT NULL',
         'pfk-related_instrument_id' =>
            '  `pfk-related_instrument_id` int(10) unsigned NOT NULL'
      },
      'engine' => 'InnoDB',
      'is_col' => {
         'sort_order'                => 1,
         'pfk-source_instrument_id'  => 1,
         'pfk-related_instrument_id' => 1
      },
      'is_numeric' => {
         'sort_order'                => 1,
         'pfk-source_instrument_id'  => 1,
         'pfk-related_instrument_id' => 1
      },
      'type_for' => {
         'sort_order'                => 'int',
         'pfk-source_instrument_id'  => 'int',
         'pfk-related_instrument_id' => 'int'
      },
      'is_nullable' => {}
   },
   'Hyphens in indexed columns',
);

$tbl = $tp->parse( load_file('samples/ndb_table.sql') );
is_deeply(
   $tbl,
   {  cols        => [qw(id)],
      col_posn    => { id => 0 },
      is_col      => { id => 1 },
      is_autoinc  => { id => 1 },
      null_cols   => [],
      is_nullable => {},
      clustered_key => undef,
      keys        => {
         PRIMARY => {
            cols         => [qw(id)],
            is_unique    => 1,
            is_col       => { id => 1 },
            name         => 'PRIMARY',
            type         => 'BTREE',
            col_prefixes => [undef],
            is_nullable  => 0,
            colnames     => '`id`',
         }
      },
      defs => { id => '  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT' },
      numeric_cols => [qw(id)],
      is_numeric   => { id => 1 },
      engine       => 'ndbcluster',
      type_for     => { id => 'bigint' },
   },
   'NDB table',
);

$tbl = $tp->parse( load_file('samples/mixed-case.sql') );
is_deeply(
   $tbl,
   {  cols         => [qw(a b mixedcol)],
      col_posn     => { a => 0, b => 1, mixedcol => 2 },
      is_col       => { a => 1, b => 1, mixedcol => 1 },
      is_autoinc   => { a => 0, b => 0, mixedcol => 0 },
      null_cols    => [qw(a b mixedcol)],
      is_nullable  => { a => 1, b => 1, mixedcol => 1 },
      clustered_key => undef,
      keys         => {
         mykey => {
            colnames     => '`a`,`b`,`mixedcol`',
            cols         => [qw(a b mixedcol)],
            col_prefixes => [undef, undef, undef],
            is_col       => { a => 1, b => 1, mixedcol => 1 },
            is_nullable  => 3,
            is_unique    => 0,
            type         => 'BTREE',
            name         => 'mykey',
         },
      },
      defs         => {
         a => '  `a` int(11) default NULL',
         b => '  `b` int(11) default NULL',
         mixedcol => '  `mixedcol` int(11) default NULL',
      },
      numeric_cols => [qw(a b mixedcol)],
      is_numeric   => { a => 1, b => 1, mixedcol => 1 },
      engine       => 'MyISAM',
      type_for     => { a => 'int', b => 'int', mixedcol => 'int' },
   },
   'Mixed-case identifiers',
);

# #############################################################################
# Test get_fks()
# #############################################################################
is_deeply(
   $tp->get_fks( load_file('samples/one_key.sql') ),
   {},
   'no fks'
);

is_deeply(
   $tp->get_fks( load_file('samples/one_fk.sql') ),   
   {
      't1_ibfk_1' => {
         name            => 't1_ibfk_1',
         colnames        => '`a`',
         cols            => ['a'],
         parent_tbl      => '`t2`',
         parent_colnames => '`a`',
         parent_cols     => ['a'],
      },
   },
   'one fk'
);

is_deeply(
   $tp->get_fks( load_file('samples/one_fk.sql'), {database=>'foo'} ),   
   {
      't1_ibfk_1' => {
         name            => 't1_ibfk_1',
         colnames        => '`a`',
         cols            => ['a'],
         parent_tbl      => '`foo`.`t2`',
         parent_colnames => '`a`',
         parent_cols     => ['a'],
      },
   },
   'one fk with default database'
);

is_deeply(
   $tp->get_fks( load_file('samples/issue_331.sql') ),   
   {
      'fk_1' => {
         name            => 'fk_1',
         colnames        => '`id`',
         cols            => ['id'],
         parent_tbl      => '`issue_331_t1`',
         parent_colnames => '`t1_id`',
         parent_cols     => ['t1_id'],
      },
      'fk_2' => {
         name            => 'fk_2',
         colnames        => '`id`',
         cols            => ['id'],
         parent_tbl      => '`issue_331_t1`',
         parent_colnames => '`t1_id`',
         parent_cols     => ['t1_id'],
      }
   },
   'two fks (issue 331)'
);

# #############################################################################
# Sandbox tests
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 8 unless $dbh;

   $sb->load_file('master', 'samples/check_table.sql');

   # msandbox user does not have GRANT privs.
   my $root_dbh = DBI->connect(
      "DBI:mysql:host=127.0.0.1;port=12345", 'root', 'msandbox',
      { PrintError => 0, RaiseError => 1 });
   $root_dbh->do("GRANT SELECT ON test.* TO 'user'\@'\%'");
   $root_dbh->do('FLUSH PRIVILEGES');
   $root_dbh->disconnect();

   my $user_dbh = DBI->connect(
      "DBI:mysql:host=127.0.0.1;port=12345", 'user', undef,
      { PrintError => 0, RaiseError => 1 });
   ok(
      $tp->check_table(
         dbh => $dbh,
         db  => 'mysql',
         tbl => 'db',
      ),
      'Table exists'
   );
   ok(
      !$tp->check_table(
         dbh => $dbh,
         db  => 'mysql',
         tbl => 'blahbleh',
      ),
      'Table does not exist'
   );
   ok(
      !$tp->check_table(
         dbh => $user_dbh,
         db  => 'mysql',
         tbl => 'db',
      ),
      "Table exists but user can't see it"
   );
   ok(
      !$tp->check_table(
         dbh => $user_dbh,
         db  => 'mysql',
         tbl => 'blahbleh',
      ),
      "Table does not exist and user can't see it"
   );
   ok(
      $tp->check_table(
         dbh       => $dbh,
         db        => 'test',
         tbl       => 't',
         all_privs => 1,
      ),
      "Table exists and user has full privs"
   );
   ok(
      !$tp->check_table(
         dbh       => $user_dbh,
         db        => 'test',
         tbl       => 't',
         all_privs => 1,
      ),
      "Table exists but user doesn't have full privs"
   );

   ok(
      $tp->check_table(
         dbh => $dbh,
         db  => 'test',
         tbl => 't_',
      ),
      'Table t_ exists'
   );
   ok(
      $tp->check_table(
         dbh => $dbh,
         db  => 'test',
         tbl => 't%_',
      ),
      'Table t%_ exists'
   );

   $user_dbh->disconnect();
};

SKIP: {
   skip 'Sandbox master does not have the sakila database', 2
      unless $dbh && @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')};
   is_deeply(
      [$tp->find_possible_keys(
         $dbh, 'sakila', 'film_actor', $q, 'film_id > 990  and actor_id > 1')],
      [qw(idx_fk_film_id PRIMARY)],
      'Best index for WHERE clause'
   );
   is_deeply(
      [$tp->find_possible_keys(
         $dbh, 'sakila', 'film_actor', $q, 'film_id > 990 or actor_id > 1')],
      [qw(idx_fk_film_id PRIMARY)],
      'Best index for WHERE clause with sort_union'
   );
};

# #############################################################################
# Issue 109: Test schema changes in 5.1
# #############################################################################
sub cmp_ddls {
   my ( $desc, $v1, $v2 ) = @_;

   $tbl = $tp->parse( load_file($v1) );
   my $tbl2 = $tp->parse( load_file($v2) );

   # The defs for each will differ due to string case: 'default' vs. 'DEFAULT'.
   # Everything else should be identical, though. So we'll chop out the defs,
   # compare them later, and check the rest first.
   my %defs  = %{$tbl->{defs}};
   my %defs2 = %{$tbl2->{defs}};
   $tbl->{defs}  = ();
   $tbl2->{defs} = ();
   is_deeply($tbl, $tbl2, "$desc SHOW CREATE parse identically");

   my $defstr  = '';
   my $defstr2 = '';
   foreach my $col ( keys %defs ) {
      $defstr  .= lc $defs{$col};
      $defstr2 .= lc $defs2{$col};
   }
   is($defstr, $defstr2, "$desc defs are identical (except for case)");

   return;
}

cmp_ddls('v5.0 vs. v5.1', 'samples/issue_109-01-v50.sql', 'samples/issue_109-01-v51.sql');

# #############################################################################
# Issue 132: mk-parallel-dump halts with error when enum contains backtick
# #############################################################################
$tbl = $tp->parse( load_file('samples/issue_132.sql') );
is_deeply(
   $tbl,
   {  cols         => [qw(country)],
      col_posn     => { country => 0 },
      is_col       => { country => 1 },
      is_autoinc   => { country => 0 },
      null_cols    => [qw(country)],
      is_nullable  => { country => 1 },
      clustered_key => undef,
      keys         => {},
      defs         => { country => "  `country` enum('','Cote D`ivoire') default NULL"},
      numeric_cols => [],
      is_numeric   => {},
      engine       => 'MyISAM',
      type_for     => { country => 'enum' },
   },
   'ENUM col with backtick in value (issue 132)'
);

# #############################################################################
# issue 328: remove AUTO_INCREMENT from schema for checksumming.
# #############################################################################
my $schema1 = load_file('samples/auto-increment-actor.sql');
my $schema2 = load_file('samples/no-auto-increment-actor.sql');
is(
   $tp->remove_auto_increment($schema1),
   $schema2,
   'AUTO_INCREMENT is gone',
);

# #############################################################################
# Issue 330: mk-parallel-dump halts with error when comments contain pairing `
# #############################################################################
$tbl = $tp->parse( load_file('samples/issue_330_backtick_pair_in_col_comments.sql') );
is_deeply(
   $tbl,
   {  cols         => [qw(a)],
      col_posn     => { a => 0 },
      is_col       => { a => 1 },
      is_autoinc   => { a => 0 },
      null_cols    => [qw(a)],
      is_nullable  => { a => 1 },
      clustered_key => undef,
      keys         => {},
      defs         => { a => "  `a` int(11) DEFAULT NULL COMMENT 'issue_330 `alex`'" },
      numeric_cols => [qw(a)],
      is_numeric   => { a => 1 },
      engine       => 'MyISAM',
      type_for     => { a => 'int' },
   },
   'issue with pairing backticks in column comments (issue 330)'
);

# #############################################################################
# Issue 170: mk-parallel-dump dies when table-status Data_length is NULL
# #############################################################################

# The underlying problem for issue 170 is that MySQLDump doesn't eval some
# of its queries so when MySQLFind uses it and hits a broken table it dies.

eval {
   $tp->parse(undef);
};
is(
   $EVAL_ERROR,
   '',
   'No error parsing undef ddl'
);


# #############################################################################
# Issue 295: Enhance rules for clustered keys in mk-duplicate-key-checker
# #############################################################################

# Make sure get_keys() gets a clustered index that's not the primary key.
my $ddl = load_file('samples/non_pk_ck.sql');
my (undef, $ck) = $tp->get_keys($ddl, {}, {i=>0,j=>1});
is(
   $ck,
   'i_idx',
   'Get first unique, non-nullable index as clustered key'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh) if $dbh;
exit;
