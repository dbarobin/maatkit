#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 12;

use Time::HiRes qw(usleep);

use MaatkitTest;
use Pipeline;

my $output  = '';
my $oktorun = 1;
my $retval;
my %args = (
   oktorun => \$oktorun,
);

# #############################################################################
# A simple run stopped by a proc returning and exit status.
# #############################################################################

my $pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $retval = $pipeline->execute(%args); },
);

is(
   $output,
   "proc1",
   "Pipeline ran"
);

is_deeply(
   $retval,
   {
      process_name => 'proc1',
      oktorun      => 0,
      eval_error   => '',
   },
   "Pipeline terminate as expected"
);

# #############################################################################
# Restarting the pipeline.
# #############################################################################

$oktorun = 1;
my @exit = (undef, 1);

$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      return shift @exit;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      print "proc2";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $retval = $pipeline->execute(%args); },
);

is(
   $output,
   "proc1proc1proc2",
   "Pipeline restarted"
);

# #############################################################################
# oktorun to control the loop.
# #############################################################################

$oktorun = 0;
$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      return 0;
   },
);

$output = output(
   sub { $retval = $pipeline->execute(%args); },
);

is(
   $output,
   "",
   "oktorun prevented pipeline from running"
);

is_deeply(
   $retval,
   {
      process_name => undef,
      eval_error   => '',
      oktorun      => 0,
   },
   "Pipeline terminated because not oktorun"
);

# #############################################################################
# Run multiple procs.
# #############################################################################

my $pargs = {};
$args{pipeline_data} = $pargs;

$oktorun  = 1;
$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      my ( $args ) = @_;
      $args->{foo} .= "foo";
      print "proc1";
      return $args;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      my ( $args ) = @_;
      $args->{foo} .= "bar";
      print "proc2";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $retval = $pipeline->execute(%args); },
);

is(
   $output,
   "proc1proc2",
   "Multiple procs ran"
);

is_deeply(
   $retval,
   {
      process_name => "proc2",
      eval_error   => '',
      oktorun      => 0,
   },
   "Pipeline terminated after proc2"
);

is(
   $pargs->{foo},
   "foobar",
   "Pipeline passed data hashref around"
);

# #############################################################################
# Instrumentation.
# #############################################################################
$oktorun = 1;
$pipeline = new Pipeline(instrument => 1);
$pipeline->add(
   name    => 'proc1',
   process => sub {
      usleep(500000);
      return 1;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      $oktorun = 0;
   },
);

$pipeline->execute(%args);

my $inst = $pipeline->instrumentation();
ok(
   $inst->{proc1}->{calls} = 1 && $inst->{proc2}->{calls} = 1,
   "Instrumentation counted calls"
);

ok(
   $inst->{proc1}->{time} > 0.4 && $inst->{proc1}->{time} < 0.6,
   "Instrumentation timed procs"
);

# #############################################################################
# Reset the previous ^ pipeline.
# #############################################################################
$pipeline->reset();
$inst  = $pipeline->instrumentation();
is(
   $inst->{proc1}->{calls},
   0,
   "Reset instrumentation"
);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $pipeline->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
