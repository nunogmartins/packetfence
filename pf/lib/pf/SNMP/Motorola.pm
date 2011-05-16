package pf::SNMP::Motorola;

=head1 NAME

pf::SNMP::Motorola

=head1 SYNOPSIS

The pf::SNMP::Motorola module implements an object oriented interface to 
manage Motorola RF Switches (Wireless Controllers)

=head1 STATUS

Developed and tested on RFS7000 running OS release 4.3.0.0-059R

=over

=item Supports

=over

=item Deauthentication with SNMP

=back

=back

=head1 BUGS AND LIMITATIONS

SNMPv3 support is untested.

=cut

use strict;
use warnings;
use diagnostics;

use base ('pf::SNMP');
use Log::Log4perl;

use pf::config;
use pf::util;

=head1 SUBROUTINES

=over

=cut

# CAPABILITIES
# access technology supported
sub supportsWirelessDot1x { return $TRUE; }
sub supportsWirelessMacAuth { return $TRUE; }

=item getVersion

obtain image version information from switch

=cut
sub getVersion {
    my ($this)       = @_;
    my $oid_sysDescr = '1.3.6.1.2.1.1.1.0';
    my $logger       = Log::Log4perl::get_logger( ref($this) );
    if ( !$this->connectRead() ) {
        return '';
    }
    $logger->trace("SNMP get_request for sysDescr: $oid_sysDescr");
    my $result = $this->{_sessionRead}->get_request( -varbindlist => [$oid_sysDescr] );
    my $sysDescr = ( $result->{$oid_sysDescr} || '' );

    # sysDescr sample output:
    # RFS7000 Wireless Switch, Version 4.3.0.0-059R MIB=01a

    # all non-whitespace characters grouped after the string Version
    if ( $sysDescr =~ / Version (\S+)/ ) {
        return $1;
    } else {
        $logger->warn("couldn't extract exact version information, returning SNMP System Description instead");
        return $sysDescr;
    }
}

=item parseTrap

All traps ignored

=cut
sub parseTrap {
    my ( $this, $trapString ) = @_;
    my $trapHashRef;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    # example disassociate trap on MAC 00 1B B1 8B 82 13
    # BEGIN TYPE 0 END TYPE BEGIN SUBTYPE 0 END SUBTYPE BEGIN VARIABLEBINDINGS .1.3.6.1.2.1.1.3.0 = Timeticks: (865381) 2:24:13.81|.1.3.6.1.6.3.1.1.4.1.0 = OID: .1.3.6.1.4.1.388.14.5.1.7.1.6|.1.3.6.1.4.1.388.14.5.1.7.1.1 = Hex-STRING: 00 1B B1 8B 82 13 |.1.3.6.1.4.1.388.14.3.3.1.2.2.1.1 = Counter32: 1|.1.3.6.1.4.1.388.14.4.1.4.1.1.1 = INTEGER: 31|.1.3.6.1.4.1.388.14.4.1.4.1.1.2 = INTEGER: 4|.1.3.6.1.4.1.388.14.4.1.4.1.1.4 = STRING: "disassociated"|.1.3.6.1.4.1.388.14.4.1.4.1.1.5 = Hex-STRING: 07 DA 09 1B 09 25 0F 00 |.1.3.6.1.4.1.388.14.4.1.4.1.1.8 = INTEGER: 2 END VARIABLEBINDINGS

    # example associate trap on MAC 00 1B B1 8B 82 13
    # BEGIN TYPE 0 END TYPE BEGIN SUBTYPE 0 END SUBTYPE BEGIN VARIABLEBINDINGS .1.3.6.1.2.1.1.3.0 = Timeticks: (875290) 2:25:52.90|.1.3.6.1.6.3.1.1.4.1.0 = OID: .1.3.6.1.4.1.388.14.5.1.7.1.4|.1.3.6.1.4.1.388.14.5.1.7.1.1 = Hex-STRING: 00 1B B1 8B 82 13 |.1.3.6.1.4.1.388.14.3.3.1.2.2.1.1 = Counter32: 1|.1.3.6.1.4.1.388.14.4.1.4.1.1.1 = INTEGER: 32|.1.3.6.1.4.1.388.14.4.1.4.1.1.2 = INTEGER: 4|.1.3.6.1.4.1.388.14.4.1.4.1.1.4 = STRING: "associated"|.1.3.6.1.4.1.388.14.4.1.4.1.1.5 = Hex-STRING: 07 DA 09 1B 09 26 36 00 |.1.3.6.1.4.1.388.14.4.1.4.1.1.8 = INTEGER: 2 END VARIABLEBINDINGS

    $logger->debug("trap ignored, not useful for wireless controller");
    $trapHashRef->{'trapType'} = 'unknown';

    return $trapHashRef;
}

=item deauthenticateMac

deauthenticate a MAC address from wireless network (including 802.1x)

=cut
sub deauthenticateMac {
    my ($this, $mac) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));
    my $oid_wsCcRfMuDisassociateNow = '1.3.6.1.4.1.388.14.3.2.1.12.3.1.19'; # from WS-CC-RF-MIB

    if ( !$this->isProductionMode() ) {
        $logger->info("not in production mode ... we won't write to wsCcRfMuDisassociateNow");
        return 1;
    }

    if ( !$this->connectWrite() ) {
        return 0;
    }

    # append MAC to deauthenticate to oid to set
    $oid_wsCcRfMuDisassociateNow .= '.' . mac2oid($mac);

    $logger->info("deauthenticate mac $mac from controller: " . $this->{_ip});
    $logger->trace("SNMP set_request for wsCcRfMuDisassociateNow: $oid_wsCcRfMuDisassociateNow");
    my $result = $this->{_sessionWrite}->set_request(
        -varbindlist => [ "$oid_wsCcRfMuDisassociateNow", Net::SNMP::INTEGER, $TRUE ]
    );

    if (defined($result)) {
        $logger->debug("deauthenticatation successful");
        return $TRUE;
    } else {
        $logger->warn("deauthenticatation failed with " . $this->{_sessionWrite}->error());
        return;
    }
}

=back

=head1 AUTHOR

Olivier Bilodeau <obilodeau@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2011 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start: