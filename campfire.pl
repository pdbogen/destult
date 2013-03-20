=COPYLEFT
	Copyright 2004-2013, Patrick Bogen

	This file is part of Destult2.

	Destult2 is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	Destult2 is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with Destult2; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
=cut

package campfire;

use POE::Session;
use POE qw(Component::Client::HTTP);
use HTTP::Request;
use MIME::Base64;
use XML::Simple;

sub new {
	my $self = {};
	$self->{ "campfire" } = shift;
	$self->{ "rooms" } = [];
	$self->{ "nick" } = undef;
	$self->{ "trap" } = 0;
	$self->{ "trapEnabled" } = 0;
	$self->{ "authz" } = undef;
	while( $_ = shift ) {
		print( "CAMPFIRE : Parsing Option '$_'\n" );
		my( $name, $value ) = split( /=/, $_, 2 );
		if( $name eq "trap" ) {
			if( $value == 1 ) {
				$value = "";
			}
			print( "CAMPFIRE : Enabling URL trapping using $value\n" );
			$self->{ "trap" } = $value;
			$self->{ "trapEnabled" } = 1;
		} elsif( $name eq "room" ) {
			push @{ $self->{ "rooms" } }, $value;
			print( "CAMPFIRE : Adding room '$value'\n" );
		} elsif( $name eq "token" ) {
			$self->{ "authz" } = "Basic ".encode_base64( $value.":x", "" );
		} elsif( exists( $self->{ $name } ) ) {
			print( "CAMPFIRE : Setting $name to $value\n" );
			$self->{ $name } = $value;
		}
	}
	unless( defined( $self->{ "authz" } ) ) {
		warn( "CAMPFIRE : No token provided! Not starting!\n" );
		return undef;
	}
	my $session = POE::Session->create(
		inline_states => {
			_start => \&on_start,
			connected => \&on_connected,
			send_private => \&send_private,
			send_public => \&send_public,
			send_public_to => \&send_public_to,
			do_join		=> \&do_join,
			do_poll		=> \&do_poll,
			joined => \&on_joined,
			polled => \&on_polled,
			first_poll => \&on_first_poll,
			message_sent => \&on_message_sent,
		},
		heap => {
			self => $self,
		},
	) or die( "Unable to create CAMPFIRE POE session." );

	$self->{ "ssid" } = $session->ID;
	bless( $self );
	return $self;
}

sub on_message_sent {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	my ($request_packet, $response_packet) = @_[ARG0, ARG1];

	my $response_object = $response_packet->[0];
	$request_packet->[0]->uri =~ /room\/(\d+)\/speak.xml/;
	my $room_id = $1;
	unless( $response_object->is_success ) {
		warn( "CAMPFIRE : Failed to speak in room #".$room_id.": ".$response_object->code." ".$response_object->message()."\n" );
		print( $response_object->content, "\n" );
		return;
	}
}

sub on_joined {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	my ($request_packet, $response_packet) = @_[ARG0, ARG1];

	my $response_object = $response_packet->[0];
	$request_packet->[0]->uri =~ /room\/(\d+)\/join.xml/;
	my $room_id = $1;
	unless( $response_object->is_success ) {
		warn( "CAMPFIRE : Failed to join room #".$room_id.": ".$response_object->code." ".$response_object->message()."\n" );
		return;
	}
	print( "CAMPFIRE : Successfully joined room #$room_id!\n" );
	$kernel->yield( "do_poll", $room_id, undef, 1 );
}

sub do_join {
	my( $kernel, $heap, $what ) = @_[ KERNEL, HEAP, ARG0 ];
	my $self = $heap->{ "self" };
	print( "CAMPFIRE : POSTing request to join room #".$what."\n" );
	my $req = HTTP::Request->new( "POST", "https://".$self->{ "campfire" }."/room/".$what."/join.xml", [ "Authorization", $self->{ "authz" } ] );
	$kernel->post( 
		"ua", 
		"request", 
		"joined", 
		$req
	);
}

sub do_poll {
	my( $kernel, $heap, $room, $last_message_id, $is_first ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $self = $heap->{ "self" };
	
	my $state = "polled";
	$state = "first_poll" if $is_first == 1;
	$last_message_id = 0 unless defined $last_message_id;
	
	$kernel->post(
		"ua",
		"request",
		$state,
		HTTP::Request->new( "GET", "https://".$self->{ "campfire" }."/room/".$room."/recent.xml?limit=10&since_message_id=".$last_message_id, [ "Authorization", $self->{ "authz" } ] )
	);
}

# This should retrieve everything and discard it.
sub on_first_poll {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	my ($request_packet, $response_packet) = @_[ARG0, ARG1];

	my $response_object = $response_packet->[0];
	$request_packet->[0]->uri =~ /room\/(\d+)\/recent.xml/;
	my $room_id = $1;
	$request_packet->[0]->uri =~ /since_message_id=(\d+)/;
	my $last_id = $1;

	unless( $response_object->is_success ) {
		warn( "CAMPFIRE : Initial Poll of Room #$room_id failed: ".$response_object->code." ".$response_object->message."\n" );
		warn( "CAMPFIRE : URL was: ".$request_packet->[0]->uri."\n" );
		return;
	}
	my $messages = XMLin( $response_object->content );
	if( scalar( @{$messages->{ "message" }} ) == 10 ) {
		$last_id = $messages->{ "message" }->[-1]->{ "id" }->{ "content" };
		print( "CAMPFIRE : Retrieving another 10 messages, beginning with $last_id\n" );
		$kernel->delay_set( "do_poll", 1, $room_id, $last_id, 1 );
	} elsif( scalar( @{$messages->{ "message" }} ) == 0 ) {
		print( "CAMPFIRE : First poll got an empty set, so beginning real polling at id $last_id\n" );
		$kernel->delay_set( "do_poll", 1, $room_id, $last_id, 0 );
	} else {
		if( ref( $messages->{ "message" } ) eq "ARRAY" ) {
			$last_id = $messages->{ "message" }->[-1]->{ "id" }->{ "content" };
		} else {
			$last_id = $messages->{ "message" }->{ "id" }->{ "content" };
		}
		print( "CAMPFIRE : First poll got a partial set, so beginning real polling at id $last_id\n" );
		$kernel->delay_set( "do_poll", 1, $room_id, $last_id, 0 );
	}
}

sub on_polled {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	my ($request_packet, $response_packet) = @_[ARG0, ARG1];

	my $response_object = $response_packet->[0];
	$request_packet->[0]->uri =~ /room\/(\d+)\/recent.xml/;
	my $room_id = $1;
	unless( $request_packet->[0]->uri =~ /since_message_id=(\d+)/ ) {
		warn( "CAMPFIRE : Couldn't locate 'since_message_id' in URL?!\n" );
		warn( "CAMPFIRE : URL was: ".$request_packet->[0]->uri."\n" );
	}
	my $last_id = $1;

	my $messages = XMLin( $response_object->content );

	if( exists( $messages->{ "message" } ) ) {
		if( ref( $messages->{ "message" } ) ne "ARRAY" ) {
			$messages->{ "message" } = [ $messages->{ "message" } ];
		}
		$last_id = $messages->{ "message" }->[-1]->{ "id" }->{ "content" };
	}

	$kernel->delay_set( "do_poll", 1, $room_id, $last_id, 0 );

	if( exists( $messages->{ "message" } ) ) {
		for my $message (@{$messages->{ "message" }}) {
			if( $message->{ "type" } eq "TextMessage" ) {
				print( "CAMPFIRE : Received <".$message->{ "user-id" }->{ "content" }."> ".$message->{ "body" }."\n" );
				$kernel->post(
					"core", 
					"core_public", 
					$message->{ "user-id" }->{ "content" }, 
					$message->{ "body" }, 
					$self->{ "ssid" }, 
					$message->{ "room-id" }->{ "content" },
					"send_public_to", 
					($bridged==0), 
					$self->{ "trapEnabled" } 
				);
			}
		}
	}
}

sub on_connected {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	my ($request_packet, $response_packet) = @_[ARG0, ARG1];

	my $response_object = $response_packet->[0];
	unless( $response_object->is_success ) {
		warn( "CAMPFIRE : Failed to retrieve room list: ".$response_object->message()."\n" );
		return;
	}

	my $rooms = XMLin( $response_object->content );
	for my $room( @{$self->{ "rooms" }} ) {
		$room =~ s/\+/ /g;
		my $found = 0;
		INNER: for my $actual_room ( keys %{ $rooms->{ "room" } } ) {
			if( $room eq $actual_room ) {
				$kernel->yield( "do_join", $rooms->{ "room" }->{ $actual_room }->{ "id" }->{ "content" } );
				$found = 1;
				last INNER;
			}
		}
		if( $found == 0 ) {
			warn( "CAMPFIRE : No room found with a name equal to '".$room."'\n" );
		}
	}
}

sub on_start {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };

	my $http = POE::Component::Client::HTTP->spawn(
		Alias => "ua",
		Timeout => 5,
	);
	
	$heap->{ "httpobject" } = $http;
	
	$kernel->post( "ua", "request", "connected", HTTP::Request->new( "GET", "https://".$self->{ "campfire" }."/rooms.xml", [ "Authorization", $self->{ "authz" } ] ) );

	$heap->{ "watchdog" } = 5;
	$kernel->delay_set( "watchdog", 5 );
	print( "CAMPFIRE : Started.\n" );
}

sub send_public_to {
	my( $kernel, $heap, $msg, $target ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my $self = $heap->{ "self" };
	print( "CAMPFIRE : Sending '$msg' to room #".$target->{ "dest" }."\n" );
	$msg =~ s/&/%26/g;
	my $r = "message=$msg&type=text";
	my $url = "https://".$self->{ "campfire" }."/room/".$target->{ "dest" }."/speak";
	print( "CAMPFIRE : POSTing to $url\n" );
	$kernel->post(
		"ua",
		"request",
		"message_sent",
		HTTP::Request->new( 
			"POST", 
			$url,
			[ "Authorization", $self->{ "authz" } ],
			$r
		)
	);
}

sub send_private {
	print( "CAMPFIRE : send_private not supported\n" );
}

return 1;
