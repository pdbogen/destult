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

package irc;

use POE::Session;
use POE::Component::IRC;
use Text::Wrap;


sub new {
	my $self = {};
	$self->{ "host" } = shift;
	$self->{ "channel" } = shift;
	$self->{ "nick" } = shift;
	$self->{ "port" } = 6667;
	$self->{ "password" } = "";
	$self->{ "trap" } = 0;
	$self->{ "trapEnabled" } = 0;
	$self->{ "throttle" } = 0;
	while( $_ = shift ) {
		print( "IRC : Parsing Option '$_'\n" );
		my( $name, $value ) = split( /=/, $_, 2 );
		if( $name eq "trap" ) {
			if( $value == 1 ) {
				$value = "";
			}
			print( "IRC : Enabling URL trapping using $value\n" );
			$self->{ "trap" } = $value;
			$self->{ "trapEnabled" } = 1;
		} elsif( exists( $self->{ $name } ) ) {
			print( "IRC : Setting $name to $value\n" );
			$self->{ $name } = $value;
		}
	}
	my $session = POE::Session->create(
		inline_states => {
			_start => \&on_start,
			irc_001 => \&on_connect,
			irc_public => \&on_public,
			irc_msg => \&on_private,
			irc_nick => \&on_nick,
			irc_kick => \&on_kick,
			irc_part => \&on_part,
			irc_quit => \&on_quit,
			send_private => \&send_private,
			send_public => \&send_public,
			send_public_to => \&send_public_to,
			do_abort	=> \&do_abort,
			do_join		=> \&do_join,
			do_part		=> \&do_part,
			do_mode		=> \&do_mode,
			watchdog => \&watchdog,
		},
		heap => {
			self => $self,
		},
	) or die( "Unable to create IRC POE session." );

	$self->{ "ssid" } = $session->ID;
	bless( $self );
	return $self;
}

sub do_join {
	my( $kernel, $heap, $what ) = @_[ KERNEL, HEAP, ARG0 ];
	if( $what =~ /^[#&][^ ,]+$/ ) {
		print( "IRC : Joining '$what'\n" );
		$kernel->post( $heap->{ 'ircobject' }->session_id(), "join", $what, @_[ ARG1..$#_ ] );
	} else {
		warn( "'$what' is an invalid channel name" );
	}
}

sub do_part {
	my( $kernel, $heap, $what ) = @_[ KERNEL, HEAP, ARG0 ];
	if( $what =~ /^[#&][^ ,]+$/ ) {
		print( "IRC : Parting '$what'\n" );
		$kernel->post( $heap->{ 'ircobject' }->session_id(), "part", $what );
	} else {
		warn( "'$what' is an invalid channel name" );
	}
}

sub do_abort {
	my( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	$heap->{ 'ircobject' }->{ 'send_queue' } = [];
	return;
}

sub watchdog {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };
	if( ! $heap->{ 'ircobject' }->connected() ) {
		print "IRC : Connection was lost.. reconnecting.\n";
		$heap->{ "watchdog" } *= 2;
		$kernel->post( $heap->{ 'ircobject' }->session_id(), "connect", {
			Nick		=> $self->{ "nick" },
			Username	=> "Destult2",
			Ircname		=> "Destultifier-Class Information Bot, v2",
			Server		=> $self->{ "host" },
			Port		=> $self->{ "port" },
		} );
	}
	$heap->{ 'timer' } = 0 unless defined $heap->{ 'timer' };
	$heap->{ 'timer' }++;
	# Back-up wathdog timer, in case IRC thinks it's connected but it isn't.
	if( $heap->{ 'timer' } == 60 ) {
		$kernel->post( $heap->{ 'ircobject' }->session_id(), "version" );
	}
	$kernel->delay_set( "watchdog", $heap->{ "watchdog" } );
}

sub on_start {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	my $self = $heap->{ "self" };

	my $irc = POE::Component::IRC->spawn( ) or die( "Unable to spawn IRC object." );

	$heap->{ 'ircobject' } = $irc;

	# This informs the IRC component to listen to:
	# 001 (Greeting)
	# Public (I.e., msg from a channel)
	# MSG (private message) and
	# CTCP_ACTION (/me-type actions)

	$kernel->post( $heap->{ 'ircobject' }->session_id(), "register", qw( 001 public msg nick kick part quit ) );
	$kernel->post( $heap->{ 'ircobject' }->session_id(), "connect", {
		Nick		=> $self->{ "nick" },
		Username	=> "Destult2",
		Ircname		=> "Destultifier-Class Information Bot, v2",
		Server		=> $self->{ "host" },
		Port		=> $self->{ "port" },
	} );
	$heap->{ "watchdog" } = 5;
	$kernel->delay_set( "watchdog", 5 );
	print( "IRC : Started.\n" );
}

# Connect to the channel specified by the config.
sub on_connect {
	my $heap = $_[HEAP];
	my $self = $heap->{ "self" };
	if( $self->{ "password" } ne "" ) {
		print( "IRC : Attempting to register with nickserv.\n" );
		$_[KERNEL]->post( $heap->{ 'ircobject' }->session_id(), "privmsg", "nickserv", "identify ".$self->{ "password" } );
	}
	$heap->{ "watchdog" } = 5;
	print( "IRC : Connected to irc://".$self->{ "host" }."/".$self->{ "channel" }."\n" );
	for my $chan (split( /,/, $self->{ "channel" } )) {
		my @args = split( /:/, $chan );
		my $chanName = shift @args;
		print( "IRC : Connecting to $chanName" );
		if( $#args >= 0 ) {
			print( " with arguments ".join( ',', @args ), "\n" );
			$_[KERNEL]->post( $heap->{ 'ircobject' }->session_id(), "join", $chanName, @args );
		} else {
			print( "\n" );
			$_[KERNEL]->post( $heap->{ 'ircobject' }->session_id(), "join", $chanName );
		}
	}
}

sub on_public {
	my( $kernel, $who, $msg, $dest ) = @_[ KERNEL, ARG0, ARG2, ARG1 ];
	my $bridged = 0;
	my $self = $_[HEAP]->{ "self" };
	my $nick = $self->{ "nick" };
	$who = (split( /!/, $who, 2 ))[0];
	$msg =~ s/^$nick[ ,:]+/~/i;
	
	$_[HEAP]->{ "bots" } = {} unless exists $_[HEAP]->{ "bots" };
	if( exists( $Destult::config{ "bots" }->{ uc($who) } ) ) {
		print( "CORE: Message bridged by $who\n" );
		$bridged = 1;
		# Strip source tag, if set
		$msg =~ s/^\[[^\]]*\] +//g;

		# Reassign and strip sender
		($who, $msg) = split( / /, $msg, 2 );
		$who =~ s/[<>]//g;
	}
	# Strip color
	$msg =~ s/(\x3)[0-9]{0,2}//g;
	$msg =~ s/\x02//g;
	$cmd = ( split( / /, $msg, 2 ) )[0];
	$kernel->post( "core", "core_public", $who, $msg, $self->{ "ssid" }, $dest->[0], "send_public_to", ($bridged==0), $self->{ "trapEnabled" } );
}

sub on_private {
	my( $kernel, $who, $msg ) = @_[ KERNEL, ARG0, ARG2 ];
	my $self = $_[HEAP]->{ "self" };
	$who = (split( /!/, $who, 2 ))[0];
	$msg =~ s/(\x3)[0-9]{0,2}//g;
	$msg =~ s/\x02//g;
	$cmd = ( split( / /, $msg, 2 ) )[0];
	$kernel->post( "core", "cmd", $who, $msg, $self->{ "ssid" }, $who, "send_private", 1 );
	$kernel->post( "core", "seen", $who, $msg, $self->{ "ssid" }, $who, "send_private", 1 );
}

sub send_public {
	my( $kernel, $heap, $msg ) = @_[ KERNEL, HEAP, ARG0 ];
	for my $chan (split( /,/, $self->{ "channel" } ) ) {
		$chan = (split( /:/, $chan ))[0];
		$kernel->yield( "send_public_to", $msg, { dest=>$chan, no_throttle=>1 } );
	}
}

sub send_public_to {
	my( $kernel, $heap, $msg, $target ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	use Data::Dumper;
	my $self = $heap->{ "self" };
	my $no_throttle = $target->{ "no_throttle" };
	if( $target->{ "dest" } =~ /^[#&+][\x01-\x06\x08\x09\x0B\x0C\x0E-\x1F\x21-\x2B\x2D-\x39\x3B-\xFF]+$/ ) {
		if( $no_throttle || !$self->{ "throttle" } || length $msg <= 354 ) {
			print( "IRC : =>".$target->{ "dest" }.": $msg\n" );
			local( $Text::Wrap::columns = 354 );
			my @msg = split( /\n/, wrap( '', '', $msg ) );
			for( @msg ) {
				$kernel->post( $heap->{ 'ircobject' }->session_id(), "privmsg", $target->{ "dest" }, $_ );
			}
		} else {
			$kernel->yield( "send_private", $msg, { dest=>$target->{ "src" }, src=>$target->{ "src" } } );
		}
	} else {
		print( "IRC : Could not send '$msg' to '".$target->{ "dest" }."' -- '".$target->{ "dest" }."' is not a channel\n" );
	}
}

sub send_private {
	my( $kernel, $heap, $msg, $who ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	local( $Text::Wrap::columns = 354 );
	my @msg = split( /\n/, wrap( '', '', $msg ) );
	for( @msg ) {
		$kernel->post( $heap->{ 'ircobject' }->session_id(), "notice", $who->{ "dest" }, $_ );
	}
}

sub on_kick {
	my( $kernel, $heap, $whom ) = @_[ KERNEL, HEAP, ARG2 ];
	my $self = $_[HEAP]->{ "self" };
	print( "IRC: $whom kicked\n" );
	$kernel->post( "core", "unidentify", uc( $whom ), $self->{ "ssid" } );
}

sub on_nick {
	my( $kernel, $heap, $whom ) = @_[ KERNEL, HEAP, ARG0 ];
	my $self = $_[HEAP]->{ "self" };
	$whom = ( split( /!/, $whom, 2 ) )[0];
	print( "IRC: $whom changed nick\n" );
	$kernel->post( "core", "unidentify", uc( $whom ), $self->{ "ssid" } );
}

sub on_part {
	my( $kernel, $heap, $whom ) = @_[ KERNEL, HEAP, ARG0 ];
	my $self = $_[HEAP]->{ "self" };
	$whom = ( split( /!/, $whom, 2 ) )[0];
	print( "IRC: $whom parted\n" );
	$kernel->post( "core", "unidentify", uc( $whom ), $self->{ "ssid" } );
}

sub on_quit {
	my( $kernel, $heap, $whom ) = @_[ KERNEL, HEAP, ARG0 ];
	my $self = $_[HEAP]->{ "self" };
	$whom = ( split( /!/, $whom, 2 ) )[0];
	print( "IRC: $whom quit\n" );
	$kernel->post( "core", "unidentify", uc( $whom ), $self->{ "ssid" } );
}

sub do_mode {
	my( $kernel, $heap, $channel, $mode ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
	my( $modeType, $who ) = split( ' ', $mode, 2 );
	print( "IRC: $channel $modeType $who\n" );
	$kernel->post( $heap->{ 'ircobject' }->session_id(), "mode", $channel, $modeType, $who );
}

return 1;
