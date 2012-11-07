=COPYLEFT
	Copyright 2004, Patrick Bogen

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

use YAML qw(LoadFile DumpFile);
use strict;
use warnings;

%Destult::config = (
	'IRC' => "127.0.0.1",
	'NICKNAME' => "Destult",
	'CHANNEL' => "test",
	'PASSWORD' => "",
);

# Load up the config file.
if( -e "config.yaml" ) {
	%Destult::config = %{ LoadFile( "config.yaml" ) };
	foreach( keys( %Destult::config ) ) {
		$Destult::config{ uc( $_ ) } = $Destult::config{ $_ };
		delete $Destult::config{ $_ } if $_ ne uc( $_ );
	}
	DumpFile( "config.yaml", \%Destult::config );
} else {
	DumpFile( "config.yaml", \%Destult::config );
	die( "No config file. Default written. These values are probably wrong." );
}
