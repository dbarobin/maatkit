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
# ProtocolParser package $Revision$
# ###########################################################################
package ProtocolParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

eval {
   require IO::Uncompress::Inflate;
   IO::Uncompress::Inflate->import(qw(inflate $InflateError));
};

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG};

# server is the "host:port" of the sever being watched.  It's auto-guessed if
# not specified.
sub new {
   my ( $class, %args ) = @_;

   my ($server_port) = $args{server} =~ m/:(\w+)/ if $args{server};
   $server_port      = $args{server_port} if !$server_port && $args{server_port};

   my $self = {
      server      => $args{server},
      server_port => $server_port,
      sessions    => {},
      o           => $args{o},
   };

   return bless $self, $class;
}

sub parse_packet {
   my ( $self, $packet, $misc ) = @_;

   # Save each session's packets until its closed by the client.
   # This allows us to ensure that packets are processed in order.
   if ( $self->{buffer} ) {
      my ($packet_from, $session) = $self->_get_session($packet);
      if ( $packet->{data_len} ) {
         if ( $packet_from eq 'client' ) {
            push @{$session->{client_packets}}, $packet;
            MKDEBUG && _d('Saved client packet');
         }
         else {
            push @{$session->{server_packets}}, $packet;
            MKDEBUG && _d('Saved server packet');
         }
      }

      # Process the session's packets when the client closes the connection.
      return unless ($packet_from eq 'client')
                    && ($packet->{fin} || $packet->{rst});

      my $event;
      map {
         $event = $self->_parse_packet($_, $misc);
      } sort { $a->{seq} <=> $b->{seq} }
      @{$session->{client_packets}};
      
      map {
         $event = $self->_parse_packet($_, $misc);
      } sort { $a->{seq} <=> $b->{seq} }
      @{$session->{server_packets}};

      return $event;
   }

   if ( $packet->{data_len} == 0 ) {
      # Return early if there's no TCP data.  These are usually ACK packets, but
      # they could also be FINs in which case, we should close and delete the
      # client's session.
      MKDEBUG && _d('No TCP data');
      return;
   }

   return $self->_parse_packet($packet, $misc);
}

# The packet arg should be a hashref from TcpdumpParser::parse_event().
# misc is a placeholder for future features.
sub _parse_packet {
   my ( $self, $packet, $misc ) = @_;

   my ($packet_from, $session) = $self->_get_session($packet);
   MKDEBUG && _d('State:', $session->{state});

   # Save raw packets to dump later in case something fails.
   push @{$session->{raw_packets}}, $packet->{raw_packet}
      unless $misc->{recurse};

   if ( $session->{buff} ) {
      # Previous packets were not complete so append this data
      # to what we've been buffering.
      $session->{buff_left} -= $packet->{data_len};
      if ( $session->{buff_left} > 0 ) {
         MKDEBUG && _d('Added data to buff; expecting', $session->{buff_left},
            'more bytes');
         return;
      }

      MKDEBUG && _d('Got all data; buff left:', $session->{buff_left});
      $packet->{data}       = $session->{buff} . $packet->{data};
      $packet->{data_len}  += length $session->{buff};
      $session->{buff}      = '';
      $session->{buff_left} = 0;
   }

   # Finally, parse the packet and maybe create an event.
   $packet->{data} = pack('H*', $packet->{data}) unless $misc->{recurse};
   my $event;
   if ( $packet_from eq 'server' ) {
      $event = $self->_packet_from_server($packet, $session, $misc);
   }
   elsif ( $packet_from eq 'client' ) {
      $event = $self->_packet_from_client($packet, $session, $misc);
   }
   else {
      # Should not get here.
      die 'Packet origin unknown';
   }
   MKDEBUG && _d('State:', $session->{state});

   if ( $session->{out_of_order} ) {
      MKDEBUG && _d('Session packets are out of order');
      push @{$session->{packets}}, $packet;
      $session->{ts_min}
         = $packet->{ts} if $packet->{ts} lt ($session->{ts_min} || '');
      $session->{ts_max}
         = $packet->{ts} if $packet->{ts} gt ($session->{ts_max} || '');
      if ( $session->{have_all_packets} ) {
         MKDEBUG && _d('Have all packets; ordering and processing');
         delete $session->{out_of_order};
         delete $session->{have_all_packets};
         map {
            $event = $self->_parse_packet($_, { recurse => 1 });
         } sort { $a->{seq} <=> $b->{seq} } @{$session->{packets}};
      }
   }

   MKDEBUG && _d('Done with packet; event:', Dumper($event));
   return $event;
}

sub _get_session {
   my ( $self, $packet ) = @_;

   my $src_host = "$packet->{src_host}:$packet->{src_port}";
   my $dst_host = "$packet->{dst_host}:$packet->{dst_port}";

   if ( my $server = $self->{server} ) {  # Watch only the given server.
      if ( $src_host ne $server && $dst_host ne $server ) {
         MKDEBUG && _d('Packet is not to or from', $server);
         return;
      }
   }

   # Auto-detect the server by looking for its port.
   my $packet_from;
   my $client;
   if ( $src_host =~ m/:$self->{server_port}$/ ) {
      $packet_from = 'server';
      $client      = $dst_host;
   }
   elsif ( $dst_host =~ m/:$self->{server_port}$/ ) {
      $packet_from = 'client';
      $client      = $src_host;
   }
   else {
      warn 'Packet is not to or from server: ', Dumper($packet);
      return;
   }
   MKDEBUG && _d('Client:', $client);

   # Get the client's session info or create a new session if the
   # client hasn't been seen before.
   if ( !exists $self->{sessions}->{$client} ) {
      MKDEBUG && _d('New session');
      $self->{sessions}->{$client} = {
         client      => $client,
         state       => undef,
         raw_packets => [],
         # ts -- wait for ts later.
      };
   };
   my $session = $self->{sessions}->{$client};

   return $packet_from, $session;
}

sub _packet_from_server {
   die "Don't call parent class _packet_from_server()";
}

sub _packet_from_client {
   die "Don't call parent class _packet_from_client()";
}

# The event is not yet suitable for mk-query-digest.  It lacks, for example,
# an arg and fingerprint attribute.  The event should be passed to
# HTTPEvent::make_event() to transform it.
sub make_event {
   my ( $self, $session, $packet ) = @_;
   die "Event has no attributes" unless scalar keys %{$session->{attribs}};
   die "Query has no arg attribute" unless $session->{attribs}->{arg};
   my $start_request = $session->{start_request} || 0;
   my $start_reply   = $session->{start_reply}   || 0;
   my $end_reply     = $session->{end_reply}     || 0;
   MKDEBUG && _d('Request start:', $start_request,
      'reply start:', $start_reply, 'reply end:', $end_reply);
   my $event = {
      Query_time    => $self->timestamp_diff($start_request, $start_reply),
      Transmit_time => $self->timestamp_diff($start_reply, $end_reply),
   };
   @{$event}{keys %{$session->{attribs}}} = values %{$session->{attribs}};
   return $event;
}

sub _get_errors_fh {
   my ( $self ) = @_;
   my $errors_fh = $self->{errors_fh};
   return $errors_fh if $errors_fh;

   # Errors file isn't open yet; try to open it.
   my $o = $self->{o};
   if ( $o && $o->has('tcpdump-errors') && $o->got('tcpdump-errors') ) {
      my $errors_file = $o->get('tcpdump-errors');
      MKDEBUG && _d('tcpdump-errors file:', $errors_file);
      open $errors_fh, '>>', $errors_file
         or die "Cannot open tcpdump-errors file $errors_file: $OS_ERROR";
   }

   $self->{errors_fh} = $errors_fh;
   return $errors_fh;
}

sub fail_session {
   my ( $self, $session, $reason ) = @_;
   my $errors_fh = $self->_get_errors_fh();
   if ( $errors_fh ) {
      $session->{reason_for_failure} = $reason;
      my $session_dump = '# ' . Dumper($session);
      chomp $session_dump;
      $session_dump =~ s/\n/\n# /g;
      print $errors_fh "$session_dump\n";
      {
         local $LIST_SEPARATOR = "\n";
         print $errors_fh "@{$session->{raw_packets}}";
         print $errors_fh "\n";
      }
   }
   MKDEBUG && _d('Failed session', $session->{client}, 'because', $reason);
   delete $self->{sessions}->{$session->{client}};
   return;
}

# Returns the difference between two tcpdump timestamps.
sub timestamp_diff {
   my ( $self, $start, $end ) = @_;
   return 0 unless $start && $end;
   my $sd = substr($start, 0, 11, '');
   my $ed = substr($end,   0, 11, '');
   my ( $sh, $sm, $ss ) = split(/:/, $start);
   my ( $eh, $em, $es ) = split(/:/, $end);
   my $esecs = ($eh * 3600 + $em * 60 + $es);
   my $ssecs = ($sh * 3600 + $sm * 60 + $ss);
   if ( $sd eq $ed ) {
      return sprintf '%.6f', $esecs - $ssecs;
   }
   else { # Assume only one day boundary has been crossed, no DST, etc
      return sprintf '%.6f', ( 86_400 - $ssecs ) + $esecs;
   }
}

# Takes a scalarref to a hex string of compressed data.
# Returns a scalarref to a hex string of the uncompressed data.
# The given hex string of compressed data is not modified.
sub uncompress_data {
   my ( $self, $data, $len ) = @_;
   die "I need data" unless $data;
   die "I need a len argument" unless $len;
   die "I need a scalar reference to data" unless ref $data eq 'SCALAR';
   MKDEBUG && _d('Uncompressing data');
   our $InflateError;

   # Pack hex string into compressed binary data.
   my $comp_bin_data = pack('H*', $$data);

   # Uncompress the compressed binary data.
   my $uncomp_bin_data = '';
   my $z = new IO::Uncompress::Inflate(
      \$comp_bin_data
   ) or die "IO::Uncompress::Inflate failed: $InflateError";
   my $status = $z->read(\$uncomp_bin_data, $len)
      or die "IO::Uncompress::Inflate failed: $InflateError";

   # Unpack the uncompressed binary data back into a hex string.
   # This is the original MySQL packet(s).
   my $uncomp_data = unpack('H*', $uncomp_bin_data);

   return \$uncomp_data;
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
# End HTTPProtocolParser package
# ###########################################################################
