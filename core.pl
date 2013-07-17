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

use POE::Session;
use warnings;
use strict;

POE::Session->create(
	inline_states => {
		_start => \&on_start,
		cmd => \&cmd,
		unidentify => \&unidentify,
		advertise => \&advertise,
		seen => \&seen,
		core_public => \&on_public,
	},
) or die( "Unable to create core POE session." );

sub seen {
	my( $kernel, $heap, $who, $src, $trusted ) = @_[ KERNEL, HEAP, ARG0, ARG2, ARG5 ];
	if( !exists( $heap->{ 'seen' } ) ) {
		$heap->{ 'seen' } = { };
	}
	$heap->{ 'seen' }->{ uc( $who ) } = time;
	if( exists( $heap->{ 'memo' } ) &&
	    exists( $heap->{ 'memo' }->{ uc( $who ) } ) ) {
	    if( exists( $heap->{ 'identified' }->{ $src.uc( $who ) } ) ) {
			$kernel->yield( "cmd", $who, "CHECKMEMO", $src, $heap->{ 'identified' }->{ $src.uc( $who ) }, "send_private", $trusted );
		} else {
			$kernel->yield( "cmd", $who, "COUNTMEMO", $src, $who, "send_private", $trusted );
		}
	}
}

sub on_start {
	my( $kernel, $heap ) = ( $_[KERNEL], $_[HEAP] );
	$heap->{ 'start' } = time;
	if( -e "commands.yaml" ) {
		my %source = %{ LoadFile( "commands.yaml" ) };
		for my $key ( keys %source ) {
			print( "CORE: Parsing $key..." );
			$heap->{ 'commands' }->{ $key } = eval( $source{ $key } );
			if( $@ ) {
				print( "FAILED: $@\n\n" );
				delete $heap->{ 'commands' }->{ $key };
			} else {
				print( "Done.\n" );
			}
		}
	} else {
		print( "CORE: No commands found.\n" );
	}

	if( -e "bots.yaml" ) {
		$heap->{ "bots" } = \%{ LoadFile( "bots.yaml" ) };
		print( "CORE: Bridge bots loaded.\n" );
	} else {
		print( "CORE: No bridge bots found.\n" );
	}

	if( -e "memos.yaml" ) {
		$heap->{ 'memo' } = \%{ LoadFile( "memos.yaml" ) };
		print( "CORE: Memos loaded.\n" );
	} else {
		print( "CORE: No memos found.\n" );
	}

	if( -e "factoids.yaml" ) {
		$heap->{ 'db' } = \%{ LoadFile( "factoids.yaml" ) };
		print( "CORE: Factoids loaded.\n" );
	} else {
		print( "CORE: No factoids found.\n" );
	}

	if( -e "cmdaccess.yaml" ) {
		$heap->{ 'cmdaccess' } = \%{ LoadFile( "cmdaccess.yaml" ) };
		print( "CORE: Access levels loaded.\n" );
	} else {
		$heap->{ 'cmdaccess' } = { };
	}

	if( -e "users.yaml" ) {
		$heap->{ 'users' } = \%{ LoadFile( "users.yaml" ) };
		print( "CORE: Users loaded.\n" );
	} else {
		$heap->{ 'users' } = { };
		print( "CORE: No users found.\n" );
	}
	
	if( -e "useraccess.yaml" ) {
		$heap->{ 'useraccess' } = \%{ LoadFile( "useraccess.yaml" ) };
		print( "CORE: User access loaded.\n" );
	} else {
		$heap->{ 'useraccess' } = { };
		print( "CORE: No user access found.\n" );
	}
	
	if( -e "ignored.yaml" ) {
		$heap->{ 'ignored' } = \%{ LoadFile( "ignored.yaml" ) };
		print( "CORE: Ignored users loaded.\n" );
	} else {
		$heap->{ 'ignored' } = { };
		print( "CORE: No ignored users.\n" );
	}
	
	$heap->{ 'identified' } = {};
	$heap->{ 'servers' } = [];
	$kernel->alias_set( "core" );
	print( "CORE: Started.\n" );
	for my $server ( split( / /, $Destult::config{ 'SERVERS' } ) ) {
		$server =~ m'([^:]+)://(.*)'i;
		my( $prot, $rest ) = ( $1, $2 );
		my( $host, $opts ) = split( '/', $rest, 2 );
		print( "CORE: Connect to $host over $prot: $opts\n" );
		my @opts = split( '/', $opts );
		for( my $i = 0; $i < scalar @opts; $i++ ) {
			$opts[$i] =~ s/%2B/+/g;
			$opts[$i] =~ s/%20/ /g;
			$opts[$i] =~ s/%25/%/g;
		}
		if( $prot =~ /irc/i ) {
			push @{ $heap->{ 'servers' } }, irc::new( $host, shift @opts, $Destult::config{ 'NICKNAME' }, @opts );
		} elsif( $prot =~ /campfire/i ) {
			push @{ $heap->{ 'servers' } }, campfire::new( $host, @opts );
		} else {
			die( "CORE: Unknown protocol: '$prot'" );
		}
	}
}

sub cmd {
	my( $kernel, $heap, $who, $what, $src, $dest, $replypath, $trusted ) = 
		( $_[KERNEL], $_[HEAP], $_[ARG0], $_[ARG1], $_[ARG2], $_[ARG3], $_[ARG4], $_[ARG5] );
	$what =~ s/^[~]//;
	my( $cmd, $subj ) = ( split( / /, $what, 2 ) );
	$subj = "" unless $subj;
	$subj =~ s/(^\s+)|(\s+$)//g;
	if( exists( $heap->{ 'ignored' }->{ uc( $who ) } ) ) {
		print( "CORE:!<$who> $cmd -- $subj\n" ) unless( !exists $Destult::config{ 'DEBUG' } );
		return;
	}
	print( "CORE: <$who> $cmd -- $subj\n" ) unless( !exists $Destult::config{ 'DEBUG' } );

	my $noparse = 0;
	my $no_throttle = 0;
	$cmd =~ s/^@\+/+@/;
	if( substr( $cmd, 0, 1 ) eq "+" ) {
		$noparse = 1;
		$cmd = substr( $cmd, 1 );
	}
	if( substr( $cmd, 0, 1 ) eq "@" ) {
		$no_throttle = 1;
		$cmd = substr( $cmd, 1 );
	}

	if( $Destult::config{ 'SECURITY' } =~ /high/i &&
	    !exists $heap->{ 'identified' }->{ $src.uc( $who ) } &&
	    $cmd !~ /identify|register|title|seen/i ) {
		$kernel->post( $src,
		               "send_private",
		               "$who: Destult is operating in high security mode; all use must be from identified users. Please REGISTER and then IDENTIFY.",
		               { dest=>$who, src=>$who, no_throttle=>$no_throttle, trusted => $trusted }
		);
		return;
	}

	if( exists( $heap->{ 'commands' }->{ uc( $cmd ) } ) ) {
		if( ( $Destult::config{ 'SECURITY' } =~ /high/i ||
		      exists $heap->{ 'cmdaccess' }->{ uc( $cmd ) } ) && !$trusted ) {
			print( "CORE: Rejecting access-controlled command attempt from $who (untrusted source)\n" );
			$kernel->post( $src,
			               $replypath,
			               "$who: Use of access-controled commands is not allowed from untrusted sources.",
			               { dest=>$dest, src=>$who, no_throttle=>$no_throttle, trusted => $trusted }
			);
			return;
		}
		if( !exists $heap->{ 'cmdaccess' }->{ uc( $cmd ) } || (
			exists $heap->{ 'identified' }->{ $src.uc( $who ) } &&
			accessLevel( $kernel, $heap, $heap->{ 'identified' }->{ $src.uc( $who ) }, $src ) >= $heap->{ 'cmdaccess' }->{ uc( $cmd ) } ) ) {
			&{ $heap->{ 'commands' }->{ uc( $cmd ) } }( $kernel, $heap, $who, $subj, $src, { dest => $dest, src=>$who, no_throttle => $no_throttle, trusted => $trusted }, $replypath );
		} else {
			if( exists $heap->{ 'identified' }->{ $src.uc( $who ) } ) {
				$kernel->post( $src, $replypath, "$who: Permission denied. An access level of ".$heap->{ 'cmdaccess' }->{ uc( $cmd ) }." is required for '$cmd'", { dest=>$dest, src=>$who, no_throttle=>$no_throttle, trusted => $trusted } );
			} else {
				$kernel->post( $src, $replypath, "$who: You must first IDENTIFY before using '$cmd'.", { dest=>$dest, src=>$who, no_throttle=>$no_throttle, trusted => $trusted } );
			}
		}
	} elsif( exists( $heap->{ 'db' }->{ uc( $what ) } ) && !$noparse ) {
		&{ $heap->{ 'commands' }->{ 'PARSE' } }( $kernel, $heap, $who, $what, $src, { dest => $dest, src=>$who, no_throttle => $no_throttle, trusted => $trusted }, $replypath );
	} else {
		my( $first, $rest ) = split( / /, $what, 2 );
		if( exists( $heap->{ 'db' }->{ uc( $first ) } ) ) {
			&{ $heap->{ 'commands' }->{ 'PARSE' } }( $kernel, $heap, $who, $what, $src, { dest => $dest, src=>$who, no_throttle => $no_throttle, trusted => $trusted }, $replypath );
		} else {
			$kernel->post( $src, "send_private", "Huh?", { dest => $who, src => $who, trusted => $trusted } );
		}
	}
}

sub accessLevel {
	my( $kernel, $heap, $whom, $src ) = @_;
	if( !exists( $heap->{ 'identified' }->{ $src.uc( $whom ) } ) ) {
		print( "ACC: $whom isn't idenfitied.\n" );
		return 0;
	}
	return access2( $heap->{ 'useraccess' }, $whom, {} );
}

# Put this in two parts so we don't get infinite loops.
sub access2 {
	my( $access, $whom, $visited ) = @_;
	if( exists $access->{ uc( $whom ) } ) {
		if( $access->{ uc( $whom ) } =~ /^[0-9]+$/ ) {
			print( "ACC: $whom: ".$access->{ uc( $whom ) }, "\n" );
			return $access->{ uc( $whom ) };
		} elsif( substr( $access->{ uc( $whom ) }, 0, 1 ) eq "~" ) {
			print( "ACC: $whom -> ".substr( $access->{ uc( $whom ) }, 1 ), "\n" );
			if( exists $visited->{ uc( $whom ) } ) {
				print( "ACC: Redirection loop; aborting.\n" );
				return 0;
			} else {
				$visited->{ uc( $whom ) } = 1;
				return access2( $access, substr( $access->{ uc( $whom ) }, 1 ), $visited );
			}
		}
	}
	print( "ACC: $whom has no access.\n" );
	return 0;
}

sub unidentify {
	my( $kernel, $heap, $whom, $src ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
    if( exists( $heap->{ 'identified' } ) && exists( $heap->{ 'identified' }->{ $src.uc( $whom ) } ) ) {
		delete $heap->{ 'identified' }->{ $src.uc( $whom ) };
	}
}

sub advertise {
	my( $kernel, $heap, $which ) = @_[ KERNEL, HEAP, ARG0 ];
	my( $period, $prot, $type, $targ, $message ) = @{ $heap->{ 'ads' }->[ $which ] };
	if( $period > 0 ) {
		print( "CORE: Advertisement '$message' to $prot:$type:$targ for $period valid.\n" );
		$kernel->post( $prot, $type, $message, $targ );
		$kernel->delay_set( "advertise", $period, $which );
	}
}

# This is called whenever a public message is received, from any source. In the future,
# this should check for hooks stored on the heap. TODO.
sub on_public {
	my( $kernel, $heap, $who, $what, $src, $dest, $replypath, $trusted, $trap ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG4, ARG5, ARG6 ];
	print( "CORE : Response will go to $dest via $replypath\n" );
	my $cmd = ( split( / /, $what, 2 ) )[0];
	# Check for the presence of a command
	if( $cmd =~ /^~.*/ ) {
		$kernel->yield( "cmd", $who, $what, $src, $dest, $replypath, $trusted );
	} else {
		# Handle URLs
		# TODO: Find a new place to put trap config
		if( $trap && $what =~ m!(https?://[^[:space:]]*[^[:space:].,\!'"])!i ) {
			print( "IRC : URL Trapped: '$1' from $who\n" );
			my $url = $1;
			$kernel->yield( "cmd", $who, "TITLE $url", $src, $dest, $replypath, $trusted );
		}
		# Handle Karma
		if( $what =~ m/^(?|\(([^)]+)\)--|([^ ]+)--)($| )/ ) {
			$kernel->yield( "cmd", $who, "KARMADOWN $1", $src, $dest, $replypath, $trusted );
		} elsif( $what =~ m/^(?|\(([^)]+)\)\+\+|([^ ]+)\+\+)($| )/ && $what !~ m/DC\+\+$/i ) {
			$kernel->yield( "cmd", $who, "KARMAUP $1", $src, $dest, $replypath, $trusted );
		}
	}
	$kernel->yield( "seen", $who, $what, $src, $dest, $replypath, $trusted );
}
