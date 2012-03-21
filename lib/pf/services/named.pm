package pf::services::named;

=head1 NAME

pf::services::named - helper configuration module for bind (dns daemon)

=head1 DESCRIPTION

This module contains some functions that generates the bind configuration
according to what PacketFence needs to accomplish.

=head1 CONFIGURATION AND ENVIRONMENT

Read the following configuration files: F<conf/named.conf>.

Generates the following configuration files: F<var/conf/named.conf> and F<var/named/>.

=cut

use strict;
use warnings;
use Log::Log4perl;
use Net::Netmask;
use POSIX;
use Readonly;

use pf::config;
use pf::util;

BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT_OK );
    @ISA = qw(Exporter);
    @EXPORT_OK = qw(
        generate_named_conf
    );
}

=head1 SUBROUTINES

=over


=item * generate_named_conf

=cut

sub generate_named_conf {
    my $logger = Log::Log4perl::get_logger('pf::services::named');

    my %tags;
    $tags{'template'}    = "$conf_dir/named.conf";
    $tags{'install_dir'} = $install_dir;

    my @routed_isolation_nets_named;
    my @routed_registration_nets_named;
    my $registration_blackhole;
    my $isolation_blackhole;
    foreach my $network ( keys %ConfigNetworks ) {

        if ( $ConfigNetworks{$network}{'named'} eq 'enabled' ) {
            if ( pf::config::is_network_type_vlan_isol($network) ) {
                my $isolation_obj = new Net::Netmask( $network, $ConfigNetworks{$network}{'netmask'} );
                push @routed_isolation_nets_named, $isolation_obj;
                $isolation_blackhole = $ConfigNetworks{$network}{'dns'};

            } elsif ( pf::config::is_network_type_vlan_reg($network) ) {
                my $registration_obj = new Net::Netmask( $network, $ConfigNetworks{$network}{'netmask'} );
                push @routed_registration_nets_named, $registration_obj;
                $registration_blackhole = $ConfigNetworks{$network}{'dns'};
            }
        }
    }

    $tags{'registration_clients'} = "";
    foreach my $net ( @routed_registration_nets_named ) {
        $tags{'registration_clients'} .= $net . "; ";
    }

    $tags{'isolation_clients'} = "";
    foreach my $net ( @routed_isolation_nets_named ) {
        $tags{'isolation_clients'} .= $net . "; ";
    }

    parse_template( \%tags, "$conf_dir/named.conf", "$generated_conf_dir/named.conf" );

    my %tags_isolation;
    $tags_isolation{'template'} = "$conf_dir/named-isolation.ca";
    $tags_isolation{'hostname'} = $Config{'general'}{'hostname'};
    $tags_isolation{'incharge'} = "pf." . $Config{'general'}{'hostname'} . "." . $Config{'general'}{'domain'};
    $tags_isolation{'A_blackhole'} = $isolation_blackhole;
    $tags_isolation{'PTR_blackhole'} = reverse_ip($isolation_blackhole) . ".in-addr.arpa.";
    parse_template(\%tags_isolation, "$conf_dir/named-isolation.ca", "$var_dir/named/named-isolation.ca", ";");

    my %tags_registration;
    $tags_registration{'template'} = "$conf_dir/named-registration.ca";
    $tags_registration{'hostname'} = $Config{'general'}{'hostname'};
    $tags_registration{'incharge'} = "pf." . $Config{'general'}{'hostname'} . "." . $Config{'general'}{'domain'};
    $tags_registration{'A_blackhole'} = $registration_blackhole;
    $tags_registration{'PTR_blackhole'} = reverse_ip($registration_blackhole) . ".in-addr.arpa.";
    parse_template(\%tags_registration, "$conf_dir/named-registration.ca", "$var_dir/named/named-registration.ca", ";");

    return 1;
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