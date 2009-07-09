---------------------------- ------ ------ ------ ------ ------ ------ ------
File                           stmt   bran   cond    sub    pod   time  total
---------------------------- ------ ------ ------ ------ ------ ------ ------
...maatkit/common/Loadavg.pm   69.1   40.0   20.0   85.7    n/a  100.0   60.1
Total                          69.1   40.0   20.0   85.7    n/a  100.0   60.1
---------------------------- ------ ------ ------ ------ ------ ------ ------


Run:          Loadavg.t
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Tue Jul  7 22:35:30 2009
Finish:       Tue Jul  7 22:35:30 2009

/home/daniel/dev/maatkit/common/Loadavg.pm

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     # This program is copyright 2008-2009 Baron Schwartz.
2                                                     # Feedback and improvements are welcome.
3                                                     #
4                                                     # THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
5                                                     # WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
6                                                     # MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
7                                                     #
8                                                     # This program is free software; you can redistribute it and/or modify it under
9                                                     # the terms of the GNU General Public License as published by the Free Software
10                                                    # Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
11                                                    # systems, you can issue `man perlgpl' or `man perlartistic' to read these
12                                                    # licenses.
13                                                    #
14                                                    # You should have received a copy of the GNU General Public License along with
15                                                    # this program; if not, write to the Free Software Foundation, Inc., 59 Temple
16                                                    # Place, Suite 330, Boston, MA  02111-1307  USA.
17                                                    # ###########################################################################
18                                                    # Loadavg package $Revision: 4088 $
19                                                    # ###########################################################################
20                                                    package Loadavg;
21                                                    
22             1                    1             6   use strict;
               1                                  2   
               1                                105   
23             1                    1             5   use warnings FATAL => 'all';
               1                                  2   
               1                                  8   
24                                                    
25             1                    1             6   use List::Util qw(sum);
               1                                  2   
               1                                 12   
26             1                    1            10   use Time::HiRes qw(time);
               1                                  4   
               1                                  5   
27             1                    1             7   use English qw(-no_match_vars);
               1                                  3   
               1                                  8   
28                                                    
29             1                    1             6   use constant MKDEBUG => $ENV{MKDEBUG};
               1                                  3   
               1                                 10   
30                                                    
31                                                    sub new {
32             1                    1             5      my ( $class ) = @_;
33             1                                 17      return bless {}, $class;
34                                                    }
35                                                    
36                                                    # Calculates average query time by the Trevor Price method.
37                                                    sub trevorprice {
38    ***      0                    0             0      my ( $self, $dbh, %args ) = @_;
39    ***      0      0                           0      die "I need a dbh argument" unless $dbh;
40    ***      0             0                    0      my $num_samples = $args{samples} || 100;
41    ***      0                                  0      my $num_running = 0;
42    ***      0                                  0      my $start = time();
43    ***      0                                  0      my (undef, $status1)
44                                                          = $dbh->selectrow_array('SHOW /*!50002 GLOBAL*/ STATUS LIKE "Questions"');
45    ***      0                                  0      for ( 1 .. $num_samples ) {
46    ***      0                                  0         my $pl = $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} });
47    ***      0             0                    0         my $running = grep { ($_->{Command} || '') eq 'Query' } @$pl;
      ***      0                                  0   
48    ***      0                                  0         $num_running += $running - 1;
49                                                       }
50    ***      0                                  0      my $time = time() - $start;
51    ***      0      0                           0      return 0 unless $time;
52    ***      0                                  0      my (undef, $status2)
53                                                          = $dbh->selectrow_array('SHOW /*!50002 GLOBAL*/ STATUS LIKE "Questions"');
54    ***      0                                  0      my $qps = ($status2 - $status1) / $time;
55    ***      0      0                           0      return 0 unless $qps;
56    ***      0                                  0      return ($num_running / $num_samples) / $qps;
57                                                    }
58                                                    
59                                                    # Calculates number of locked queries in the processlist.
60                                                    sub num_locked {
61    ***      0                    0             0      my ( $self, $dbh ) = @_;
62    ***      0      0                           0      die "I need a dbh argument" unless $dbh;
63    ***      0                                  0      my $pl = $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} });
64    ***      0             0                    0      my $locked = grep { ($_->{State} || '') eq 'Locked' } @$pl;
      ***      0                                  0   
65    ***      0             0                    0      return $locked || 0;
66                                                    }
67                                                    
68                                                    # Calculates loadavg from the uptime command.
69                                                    sub loadavg {
70             1                    1            11      my ( $self ) = @_;
71             1                               2899      my $str = `uptime`;
72             1                                 11      chomp $str;
73    ***      1     50                          12      return 0 unless $str;
74             1                                 29      my ( $one ) = $str =~ m/load average:\s+(\S[^,]*),/;
75    ***      1            50                   47      return $one || 0;
76                                                    }
77                                                    
78                                                    # Calculates slave lag.  If the slave is not running, returns 0.
79                                                    sub slave_lag {
80             1                    1             5      my ( $self, $dbh ) = @_;
81    ***      1     50                           5      die "I need a dbh argument" unless $dbh;
82             1                                 47      my $sl = $dbh->selectall_arrayref('SHOW SLAVE STATUS', { Slice => {} });
83    ***      1     50                          10      if ( $sl ) {
84             1                                  4         $sl = $sl->[0];
85             1                                  8         my ( $key ) = grep { m/behind_master/i } keys %$sl;
              33                                103   
86    ***      1     50     50                   31         return $key ? $sl->{$key} || 0 : 0;
87                                                       }
88    ***      0                                  0      return 0;
89                                                    }
90                                                    
91                                                    # Calculates any metric from SHOW STATUS, either absolute or over a 1-second
92                                                    # interval.
93                                                    sub status {
94             1                    1            13      my ( $self, $dbh, %args ) = @_;
95    ***      1     50                           6      die "I need a dbh argument" unless $dbh;
96             1                                  3      my (undef, $status1)
97                                                          = $dbh->selectrow_array("SHOW /*!50002 GLOBAL*/ STATUS LIKE '$args{metric}'");
98    ***      1     50                         388      if ( $args{incstatus} ) {
99    ***      0                                  0         sleep(1);
100   ***      0                                  0         my (undef, $status2)
101                                                            = $dbh->selectrow_array("SHOW /*!50002 GLOBAL*/ STATUS LIKE '$args{metric}'");
102   ***      0                                  0         return $status2 - $status1;
103                                                      }
104                                                      else {
105            1                                 13         return $status1;
106                                                      }
107                                                   }
108                                                   
109                                                   # Returns the highest value for a given section and var, like transactions
110                                                   # and lock_wait_time.
111                                                   sub innodb_status {
112            2                    2            30      my ( $self, %args ) = @_;
113            2                                 16      foreach my $arg ( qw(dbh InnoDBStatusParser section var) ) {
114   ***      8     50                          39         die "I need a $arg argument" unless $args{$arg};
115                                                      }
116            2                                  7      my $dbh     = $args{dbh};
117            2                                  7      my $is      = $args{InnoDBStatusParser};
118            2                                  9      my $section = $args{section};
119            2                                  6      my $var     = $args{var};
120                                                   
121                                                      # Get and parse SHOW INNODB STATUS text.
122            2                                  5      my ($status_text, undef) = $dbh->selectrow_array("SHOW INNODB STATUS");
123   ***      2     50                         946      if ( !$status_text ) {
124   ***      0                                  0         MKDEBUG && _d('SHOW INNODB STATUS failed');
125   ***      0                                  0         return 0;
126                                                      }
127            2                                 25      my $idb_stats = $is->parse($status_text);
128                                                   
129            2    100                          21      if ( !exists $idb_stats->{$section} ) {
130            1                                  3         MKDEBUG && _d('idb status section', $section, 'does not exist');
131            1                                 50         return 0;
132                                                      }
133                                                   
134                                                      # Each section should be an arrayref.  Go through each set of vars
135                                                      # and find the highest var that we're checking.
136            1                                  3      my $value = 0;
137            1                                  3      foreach my $vars ( @{$idb_stats->{$section}} ) {
               1                                  5   
138            1                                  3         MKDEBUG && _d($var, '=', $vars->{$var});
139   ***      1     50     33                   16         $value = $vars->{$var} && $vars->{$var} > $value ? $vars->{$var} : $value;
140                                                      }
141                                                   
142            1                                  2      MKDEBUG && _d('Highest', $var, '=', $value);
143            1                                 42      return $value;
144                                                   }
145                                                   
146                                                   sub _d {
147            1                    1             7      my ($package, undef, $line) = caller 0;
148   ***      2     50                           9      @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
               2                                  9   
               2                                 11   
149            1                                  4           map { defined $_ ? $_ : 'undef' }
150                                                           @_;
151            1                                  3      print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
152                                                   }
153                                                   
154                                                   1;
155                                                   
156                                                   # ###########################################################################
157                                                   # End Loadavg package
158                                                   # ###########################################################################


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
39    ***      0      0      0   unless $dbh
51    ***      0      0      0   unless $time
55    ***      0      0      0   unless $qps
62    ***      0      0      0   unless $dbh
73    ***     50      0      1   unless $str
81    ***     50      0      1   unless $dbh
83    ***     50      1      0   if ($sl)
86    ***     50      1      0   $key ? :
95    ***     50      0      1   unless $dbh
98    ***     50      0      1   if ($args{'incstatus'}) { }
114   ***     50      0      8   unless $args{$arg}
123   ***     50      0      2   if (not $status_text)
129          100      1      1   if (not exists $$idb_stats{$section})
139   ***     50      1      0   $$vars{$var} && $$vars{$var} > $value ? :
148   ***     50      2      0   defined $_ ? :


Conditions
----------

and 3 conditions

line  err      %     !l  l&&!r   l&&r   expr
----- --- ------ ------ ------ ------   ----
139   ***     33      0      0      1   $$vars{$var} && $$vars{$var} > $value

or 2 conditions

line  err      %      l     !l   expr
----- --- ------ ------ ------   ----
40    ***      0      0      0   $args{'samples'} || 100
47    ***      0      0      0   $$_{'Command'} || ''
64    ***      0      0      0   $$_{'State'} || ''
65    ***      0      0      0   $locked || 0
75    ***     50      1      0   $one || 0
86    ***     50      0      1   $$sl{$key} || 0


Covered Subroutines
-------------------

Subroutine    Count Location                                      
------------- ----- ----------------------------------------------
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:22 
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:23 
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:25 
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:26 
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:27 
BEGIN             1 /home/daniel/dev/maatkit/common/Loadavg.pm:29 
_d                1 /home/daniel/dev/maatkit/common/Loadavg.pm:147
innodb_status     2 /home/daniel/dev/maatkit/common/Loadavg.pm:112
loadavg           1 /home/daniel/dev/maatkit/common/Loadavg.pm:70 
new               1 /home/daniel/dev/maatkit/common/Loadavg.pm:32 
slave_lag         1 /home/daniel/dev/maatkit/common/Loadavg.pm:80 
status            1 /home/daniel/dev/maatkit/common/Loadavg.pm:94 

Uncovered Subroutines
---------------------

Subroutine    Count Location                                      
------------- ----- ----------------------------------------------
num_locked        0 /home/daniel/dev/maatkit/common/Loadavg.pm:61 
trevorprice       0 /home/daniel/dev/maatkit/common/Loadavg.pm:38 

