package pf::pfcmd::checkup;

=head1 NAME

pf::pfcmd::checkup - pfcmd's checkup tasks

=head1 DESCRIPTION

This modules holds all the tests performed by 'pfcmd checkup' which is a general configuration sanity test.

=cut

use strict;
use warnings;

use Fcntl ':mode'; # symbolic file permissions
use Try::Tiny;
use Readonly;

use pf::config;
use pf::util;
use pf::services;
use pf::trigger;

use lib $conf_dir;

BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT );
    @ISA = qw(Exporter);
    @EXPORT = qw(
        sanity_check
    );
}

# Error levels
Readonly our $FATAL => "FATAL";
Readonly our $WARN => "WARNING";

# Pieces
Readonly our $SEVERITY => "severity";
Readonly our $MESSAGE => "message";

our @problems;

=head1 SUBROUTINES

=over

=item add_problem

Add a problem to the problem list.

add_problem( severity, message );

=cut
sub add_problem {
    my ($severity, $message) = @_;

    push @problems, {
        $SEVERITY => $severity,
        $MESSAGE => $message
    };
}

=item sanity_check

Returns an array of hashes of the form ( $SEVERITY => ... , $MESSAGE => ... )

=cut
sub sanity_check {
    my (@services) = @_;

    # emptying problem list
    @problems = ();
    print "Checking configuration sanity...\n";

    # SELinux test only for RedHat based distros
    if ( -e "/etc/redhat-release" && `getenforce` =~ /^Enforcing/ ) {
        add_problem( $WARN, 
            'SELinux is in enforcing mode. This is currently not supported in PacketFence'
        );
    }

    if (!-f $lib_dir . '/pf/pfcmd/pfcmd_pregrammar.pm') {
        add_problem( $FATAL, 
            "You are missing a critical file for PacketFence's proper operation. " .
            "See instructions to re-create the file in: perldoc $lib_dir/pf/pfcmd/pfcmd.pm"
        );
    }

    service_exists(@services);
    interfaces_defined();
    interfaces();

    if ( isenabled($Config{'services'}{'radiusd'} ) ) {
        freeradius();
    }

    if ( isenabled($Config{'trapping'}{'detection'}) ) {
        ids_snort();
    }

    scan() if ( lc($Config{'scan'}{'engine'}) ne "none" );
    scan_openvas() if ( lc($Config{'scan'}{'engine'}) eq "openvas" );

    billing() if ( isenabled($Config{'registration'}{'billing_engine'}) );

    database();
    network();
    inline() if (is_inline_enforcement_enabled());
    apache();
    web_admin();
    registration();
    is_config_documented();
    extensions();
    permissions();
    violations();
    switches();
    unsupported();

    return @problems;
}

sub service_exists {
    my (@services) = @_;

    foreach my $service (@services) {
        my $exe = ( $Config{'services'}{"${service}_binary"} || "$install_dir/sbin/$service" );
        if ( !-e $exe ) {
            add_problem( $FATAL, "$exe for $service does not exist !" );
        }
    }
}

=item interfaces_defined

check the config file to make sure interfaces are fully defined

=cut
sub interfaces_defined {

    my $nb_management_interface = 0;

    foreach my $interface ( tied(%Config)->GroupMembers("interface") ) {
        my %int_conf = %{$Config{$interface}};
        my $int_with_no_config_required_regexp = qr/(?:monitor|dhcplistener|dhcp-listener|high-availability)/;

        if (!defined($int_conf{'type'}) || $int_conf{'type'} !~ /$int_with_no_config_required_regexp/) {
            if (!defined $int_conf{'ip'} || !defined $int_conf{'mask'} || !defined $int_conf{'gateway'}) {
                add_problem( $FATAL, "incomplete network information for $interface" );
            }
        }

        my $int_types = qr/(?:internal|management|managed|monitor|dhcplistener|dhcp-listener|high-availability)/;
        if (defined($int_conf{'type'}) && $int_conf{'type'} !~ /$int_types/) {
            add_problem( $FATAL, "invalid network type $int_conf{'type'} for $interface" );
        }
 
        $nb_management_interface++ if (defined($int_conf{'type'}) && $int_conf{'type'} =~ /management|managed/);
    }

    if ($nb_management_interface != 1)  {
        add_problem( $FATAL, "please define exactly one management interface" );
    }
}

=item interfaces

check the Netmask objs and make sure a managed and internal interface exist

=cut
sub interfaces {

    if ( !scalar(get_internal_devs()) ) {
        add_problem( $FATAL, "internal network(s) not defined!" );
    }

    my %seen;
    my @network_interfaces;
    push @network_interfaces, get_internal_devs();
    push @network_interfaces, $management_network->tag("int") if (defined($management_network));
    foreach my $interface (@network_interfaces) {
        my $device = "interface " . $interface;

        if ( !($Config{$device}{'mask'} && $Config{$device}{'ip'}
            && $Config{$device}{'gateway'} && $Config{$device}{'type'})
            && !$seen{$interface}) {
                add_problem( $FATAL, 
                    "Incomplete network information for $device. " .
                    "IP, network mask, gateway and type required."
                );
        }
        $seen{$interface} = 1;

        foreach my $type ( split( /\s*,\s*/, $Config{$device}{'type'} ) ) {
            if ($type eq $IF_INTERNAL && !defined($Config{$device}{'enforcement'})) {
                add_problem( $FATAL, 
                    "Incomplete network information for $device. " .
                    "Enforcement technique must be defined on an internal interface. " .
                    "Your choices are: $IF_ENFORCEMENT_VLAN or $IF_ENFORCEMENT_INLINE. " . 
                    "If unsure refer to the documentation."
                );
            }

            if ($type eq 'managed') {
                add_problem( $WARN, 
                    "Interface type 'managed' is deprecated and will be removed in future versions of PacketFence. " .
                    "You should use the 'management' keyword instead. " .
                    "Seen on interface $interface."
                );
            }
        }
    }
}


=item freeradius

Validation related to the FreeRADIUS daemon

=cut
sub freeradius {

    if ( !-x $Config{'services'}{'radiusd_binary'} ) {
        add_problem( $FATAL, "radiusd binary is not executable / does not exist!" );
    }
}


=item ids_snort

Validation related to the Snort IDS usage 

=cut
sub ids_snort {

    # make sure a monitor device is present if snort is enabled
    if ( !$monitor_int ) {
        add_problem( $FATAL, 
            "monitor interface not defined, please disable trapping.dectection " . 
            "or set an interface type=...,monitor in pf.conf"
        );
    }

    # make sure named pipe 'alert' is present if snort is enabled
    my $snortpipe = "$install_dir/var/alert";
    if ( !-p $snortpipe ) {
        if ( !POSIX::mkfifo( $snortpipe, oct(666) ) ) {
            add_problem( $FATAL, "snort alert pipe ($snortpipe) does not exist and unable to create it" );
        }
    }

    if ( !-x $Config{'services'}{'snort_binary'} ) {
        add_problem( $FATAL, "snort binary is not executable / does not exist!" );
    }

}

=item scan

Validation related to the vulnerability scanning engine option.

=cut
sub scan {
    # Check if the configuration provided scan engine is instanciable
    my $scan_engine = 'pf::scan::' . lc($Config{'scan'}{'engine'});

    try {
        eval "use $scan_engine;";
        die($@) if ($@);
        my $scan = $scan_engine->new(
            host => $Config{'scan'}{'host'},
            user => $Config{'scan'}{'user'},
            pass => $Config{'scan'}{'pass'},
        );
    } catch {
        chomp($_);
        add_problem( $FATAL, "SCAN: Incorrect scan engine declared in pf.conf: $_" );
    };
}

=item scan_openvas

Validation related to the OpenVAS vulnerability scanning engine usage.

=cut
sub scan_openvas {
    # Check if the mandatory informations are provided in the config file
    if ( !$Config{'scan'}{'openvas_configid'} ) {
        add_problem( $WARN, "SCAN: The use of OpenVas as a scanning engine require to fill the " . 
                "scan.openvas_configid field in pf.conf" );
    }
    if ( !$Config{'scan'}{'openvas_reportformatid'} ) {
        add_problem( $WARN, "SCAN: The use of OpenVas as a scanning engine require to fill the " . 
                "scan.openvas_reportformatid field in pf.conf");
    }
}

=item network

Configuration validation of the network portion of the config

=cut
sub network {

    # network size warning
    my $internal_total;
    foreach my $internal_net (@internal_nets) {
        if ( $internal_net->bits() < 16 && isenabled( $Config{'general'}{'caching'} ) ) {
            add_problem( $WARN, "network $internal_net is larger than a /16 - you should disable general.caching!" );
        }
        $internal_total += $internal_net->size();
    }

    # make sure trapping.passthrough=proxy if network.mode is set to vlan
    if ( $Config{'trapping'}{'passthrough'} eq 'iptables' ) {
        add_problem( $WARN, 
            "iptables based passthrough (trapping.passthrough) is incompatible with current PacketFence release. " .
            "Please file a ticket if you need this feature back."
        );
    }

    # make sure that networks.conf is not empty when services.dhcpd
    # is enabled
    if (isenabled($Config{'services'}{'dhcpd'}) && ((!-e "$conf_dir/networks.conf") || (-z "$conf_dir/networks.conf"))){
        add_problem( $FATAL, "networks.conf cannot be empty when services.dhcpd is enabled" );
    }

    # make sure that networks.conf is not empty when services.named
    # is enabled
    if (isenabled($Config{'services'}{'named'}) && ((!-e "$conf_dir/networks.conf") || (-z "$conf_dir/networks.conf"))){
        add_problem( $FATAL, "networks.conf cannot be empty when services.named is enabled" );
    }

    foreach my $network (keys %ConfigNetworks) {
        # shorter, more convenient accessor
        my %net = %{$ConfigNetworks{$network}};

        # isolation / registration deprecation (now vlan-isolation and vlan-registration)
        # TODO once isolation / registration deprecated use pf::config::get_network_type($network), test for undef
        # and upgrade to $FATAL
        if (defined($net{'type'}) && $net{'type'} =~ /^isolation$|^registration$/i) {
            add_problem( $WARN,
                "networks.conf type isolation or registration is deprecated in favor of " . 
                "vlan-isolation and vlan-registration. " . 
                "Make sure to update your configuration as the old keywords will be removed in the future. " .
                "Network $network"
            );
        }

        # pf_gateway deprecated in favor of next_hop
        # TODO upgrade to FATAL once pf_gateway officially deprecated (somewhere in 2012)
        if (defined($net{'pf_gateway'}) && $net{'pf_gateway'} ne '') {
            add_problem( $WARN,
                "networks.conf pf_gateway is deprecated in favor of next_hop. " . 
                "Make sure to update your configuration as the old parameters will be removed in the future. " .
                "Network $network"
            );
        }

        # validate dns entry if named is enabled
        if ($net{'named'} =~ /enabled/i) {
            if (!valid_ip($net{'dns'})) {
                add_problem( $FATAL, "networks.conf: DNS IP is not valid for network $network" );
            }
        }

        # mandatory fields if we run DHCP (should be most cases)
        if ($net{'dhcpd'} =~ /enabled/i) {
            my $netmask_valid = (defined($net{'netmask'}) && valid_ip($net{'netmask'}));
            my $gw_valid = (defined($net{'gateway'}) && valid_ip($net{'gateway'}));
            my $domainname_valid = (defined($net{'domain-name'}) && $net{'domain-name'} !~ /^\s*$/);
            my $range_valid = (
                defined($net{'dhcp_start'}) && $net{'dhcp_start'} !~ /^\s*$/ &&
                defined($net{'dhcp_end'}) && $net{'dhcp_end'} !~ /^\s*$/
            );
            my $default_lease_valid = (
                defined($net{'dhcp_default_lease_time'}) && $net{'dhcp_default_lease_time'} =~ /^\d+$/
            );
            my $max_lease_valid = ( defined($net{'dhcp_max_lease_time'}) && $net{'dhcp_max_lease_time'} =~ /^\d+$/ );
            if (!($netmask_valid && $gw_valid && $domainname_valid && $range_valid && $default_lease_valid && $max_lease_valid)) {
                add_problem( $FATAL, "networks.conf: Incomplete DHCP information for network $network" );
            }
        }

        # run inline network tests
        network_inline($network) if (pf::config::is_network_type_inline($network));
    }
}


=item network_inline

Tests that validate the configuration of an inline network.

=cut
sub network_inline {
    my ($network) = @_;
    # shorter, more convenient accessor
    my %net = %{$ConfigNetworks{$network}};

    # inline interface with named=disabled is not what you want
    if ( $net{'named'} =~ /disabled/i ) {
        add_problem( $WARN,
                "networks.conf type inline with named disabled is *not* what you want. " .
                "Since we're DNATTING DNS if in an unreg or isolated state, you'll want to change that to enabled."
        );
    }

    # inline interfaces should have at least one local gateway
    my $found = 0;
    foreach my $int (@internal_nets) {
        if ( $Config{ 'interface ' . $int->tag('int') }{'ip'} eq $net{'gateway'} ) {
            $found = 1;
            next;
        }
    }
    if ( !$found ) {
        add_problem( $WARN, 
            "networks.conf $network gateway ($net{'gateway'}) is not bound to an internal interface. " .
            "Assume your configuration is wrong unless you know what you are doing."
        );
    }
}

=item inline

If some interfaces are configured to run in inline enforcement then these tests will run

=cut
sub inline {

    # make sure trapping.passthrough=proxy if network.mode is set to vlan
    if ( $Config{'trapping'}{'passthrough'} eq 'proxy' ) {
        add_problem( $WARN, 
            "Proxy passthrough (trapping.passthrough) is untested with inline enforcement and might not work. " .
            "If you don't understand the warning you can safely ignore it you won't be affected. "
        );
    }

    my $result = pf_run("cat /proc/sys/net/ipv4/ip_forward");
    if ($result ne "1\n") {
        add_problem( $WARN, 
            "inline mode needs ip_forward enabled to work properly. " . 
            "Refer to the administration guide to enable ip_forward."
        );
    }
}

=item database

database check

=cut
sub database {

    try {

        # make sure pid 1 exists
        require pf::person;
        if ( !pf::person::person_exist(1) ) {
            add_problem( $FATAL, "person user id 1 must exist - please reinitialize your database" );
        }

    } catch {
        if ($_ =~ /unable to connect to database/) {
            add_problem( 
                $FATAL, 
                "Unable to connect to your database. " 
                . "Please verify your connection settings in conf/pf.conf and make sure that it is started."
            );
        } else {
            add_problem( $FATAL, "Unexpected database problem: $_" );
        }
    };

}

=item web_admin

Web Administration interface checks

=cut
sub web_admin {

    # make sure admin port exists
    if ( !$Config{'ports'}{'admin'} ) {
        add_problem( $FATAL, "please set the web admin port in pf.conf (ports.admin)" );
    }

}

=item registration

Registration configuration sanity

=cut
sub registration {

    # warn when scan.registration=enabled and trapping.registration=disabled
    if ( isenabled( $Config{'scan'}{'registration'} ) && isdisabled( $Config{'trapping'}{'registration'} ) ) {
        add_problem( $WARN, "scan.registration is enabled but trapping.registration is not ... this is strange!" );
    }

    # registration.skip_mode validation
    if ( $Config{'registration'}{'skip_mode'} eq "deadline" && !$Config{'registration'}{'skip_deadline'} ) {
        add_problem( $FATAL,
            "pf.conf value registration.skip_deadline is mal-formed or null! " . 
            "(format should be that of the 'date' command)"
        );
    } elsif ( $Config{'registration'}{'skip_mode'} eq "windows" && !$Config{'registration'}{'skip_window'} ) {
        add_problem( $FATAL, "pf.conf value registration.skip_window is not defined!" );
    }

    # registration.expire_mode validation
    if ( $Config{'registration'}{'expire_mode'} eq "deadline" && !$Config{'registration'}{'expire_deadline'} ) {
        add_problem( $FATAL,
            "pf.conf value registration.expire_deadline is mal-formed or null! " . 
            "(format should be that of the 'date' command)"
        );
    } elsif ( $Config{'registration'}{'expire_mode'} eq "window" && !$Config{'registration'}{'expire_window'} ) {
        add_problem( $FATAL, "pf.conf value registration.expire_window is not defined!" );
    }

    # make sure that expire_mode session is disabled in VLAN isolation
    if (lc($Config{'registration'}{'expire_mode'}) eq 'session') {
        add_problem( $FATAL, 
            "automatic node expiration mode ".$Config{'registration'}{'expire_mode'} . " " .
            "is incompatible with current PacketFence release. Please file a ticket if you need this feature."
        );
    }

}

# TODO Consider moving to a test
sub is_config_documented {

    #compare configuration with documentation
    tie my %myconfig, 'Config::IniFiles', (
        -file   => $config_file,
        -import => Config::IniFiles->new( -file => $default_config_file )
    );
    tie my %documentation, 'Config::IniFiles', ( -file => $conf_dir . "/documentation.conf" );
    my @errors = @Config::IniFiles::errors;
    if ( scalar(@errors) ) {
        my $message = join( "\n", @errors ) . "\n";
        add_problem( $FATAL, "problem reading documentation.conf. Error: $message" );
    }

    #starting with documentation vs configuration
    #i.e. make sure that pf.conf contains everything defined in
    #documentation.conf
    foreach my $section ( sort tied(%documentation)->Sections ) {
        my ( $group, $item ) = split( /\./, $section );
        my $type = $documentation{$section}{'type'};

        next if ( $section =~ /^(proxies|passthroughs)$/ || $group =~ /^(interface|services)$/ );
        next if ( ( $group eq 'alerting' ) && ( $item eq 'fromaddr' ) );

        if ( defined( $Config{$group}{$item} ) ) {
            if ( $type eq "toggle" ) {
                if ( $Config{$group}{$item} !~ /^$documentation{$section}{'options'}$/ ) {
                    add_problem( $FATAL,
                        "pf.conf value $group\.$item must be one of the following: "
                        . $documentation{$section}{'options'}
                    );
                }
            } elsif ( $type eq "time" ) {
                if ( $myconfig{$group}{$item} !~ /\d+$TIME_MODIFIER_RE$/ ) {
                    add_problem( $FATAL,
                        "pf.conf value $group\.$item does not explicity define interval (eg. 7200s, 120m, 2h) " .
                        "- please define it before running packetfence"
                    );
                }
            } elsif ( $type eq "multi" ) {
                my @selectedOptions = split( /\s*,\s*/, $myconfig{$group}{$item} );
                my @availableOptions = split( /\s*[;\|]\s*/, $documentation{$section}{'options'} );
                foreach my $currentSelectedOption (@selectedOptions) {
                    if ( grep(/^$currentSelectedOption$/, @availableOptions) == 0 ) {
                        add_problem( $FATAL,
                            "pf.conf values for $group\.$item must be among the following: " .
                            $documentation{$section}{'options'} .  " but you used $currentSelectedOption. " .
                            "If you are sure of this choice, please update conf/documentation.conf"
                        );
                    }
                }
            }
        } elsif ( $Config{$group}{$item} ne "0" ) {
            add_problem( $FATAL, "pf.conf value $group\.$item is not defined!" );
        }
    }

    #and now the opposite way around
    #i.e. make sure that pf.conf does not contain more
    #than what is documented in documentation.conf
    foreach my $section (keys %Config) {
        next if ( ($section eq "proxies") || ($section eq "passthroughs") || ($section eq "")
                  || ($section =~ /^(services|interface)/));

        foreach my $item  (keys %{$Config{$section}}) {
            if ( !defined( $documentation{"$section.$item"} ) ) {
                add_problem( $FATAL, 
                    "unknown configuration parameter $section.$item ".
                    "if you added the parameter yourself make sure it is present in conf/documentation.conf"
                );
            }
        }
    }

}

=item extensions

Performs version checking of the extension points.

=cut
sub extensions {

    my @extensions = (
        { 'name' => 'Inline', 'module' => 'pf::inline::custom', 'api' => $INLINE_API_LEVEL, },
        { 'name' => 'VLAN', 'module' => 'pf::vlan::custom', 'api' => $VLAN_API_LEVEL, },
        { 'name' => 'Billing', 'module' => 'pf::billing::custom', 'api' => $BILLING_API_LEVEL, },
        { 'name' => 'SoH', 'module' => 'pf::soh::custom', 'api' => $SOH_API_LEVEL, },
        { 'name' => 'RADIUS', 'module' => 'pf::radius::custom', 'api' => $RADIUS_API_LEVEL, },
        { 'name' => 'Roles', 'module' => 'pf::roles::custom', 'api' => $ROLE_API_LEVEL, },
    );

    foreach my $extension_ref ( @extensions ) {

        try {
            # try loading it
            eval "require $extension_ref->{module}";
            # throw exceptions
            die($@) if ($@);

            if (!defined($extension_ref->{module}->VERSION())) {
                add_problem($FATAL, 
                    "$extension_ref->{name} extension point ($extension_ref->{module}) VERSION is not defined."
                );
            }
            elsif ($extension_ref->{api} > $extension_ref->{module}->VERSION()) {
                add_problem( $FATAL,
                    "$extension_ref->{name} extension point ($extension_ref->{module}) is not at the correct API level. " .
                    "Did you read the UPGRADE document?"
                );
            }
        } 
        catch {
            chomp($_);
            add_problem($FATAL, "Uncaught exception while trying to identify $extension_ref->{name} extension version: $_");
        };
    }

    # TODO we might want to re-add that to the above if we ever get 
    # catastrophic chains of extension failures that are confusing to users

    # we ignore "version check failed" or "version x required"
    # as it means that pf::vlan::custom's version is not good which we already catched above
    #if ($_ !~ /(?:version check failed)|(?:version .+ required)/) {
    #        add_problem( $FATAL, "Uncaught exception while trying to identify RADIUS extension version: $_" );
    #}

    # Authentication modules
    my @activated_auth_modules = split( /\s*,\s*/, $Config{'registration'}{'auth'} );
    # if sponsored guest authentication is enabled test the module
    if ($guest_self_registration{$SELFREG_MODE_SPONSOR}) {
        push @activated_auth_modules, $Config{'guests_self_registration'}{'sponsor_authentication'};
    }
    foreach my $auth (@activated_auth_modules) {
        my ($authenticator, $authReturn, $err);
        try {
            # try to import module and re-throw the error to catch if there's one
            eval "use authentication::$auth";
            die($@) if ($@);

            $authenticator = new {"authentication::$auth"}();
            if (!$authenticator->isa('pf::web::auth')) {
                add_problem( $FATAL,
                    "Authentication module authentication::$auth is enabled and is not of the correct object type. " .
                    "Did you read the UPGRADE document?"
                );
            }

            if (!defined($authenticator->VERSION())) { 
                add_problem( $FATAL,
                    "Authentication module authentication::$auth is enabled and its VERSION is not defined. " . 
                    "Did you read the UPGRADE document?"
                );
            } elsif ($AUTHENTICATION_API_LEVEL > $authenticator->VERSION()) { 
                add_problem( $FATAL,
                    "Authentication module authentication::$auth is enabled and is not at the correct API level. " .
                    "Did you read the UPGRADE document?"
                );
            }


        } catch {
            add_problem($FATAL, "Uncaught exception while trying to identify authentication::$auth module version: $_");
        }
    }
}

=item permissions

Checking some important permissions

=cut
sub permissions {

    # pfcmd needs to be setuid / setgid and 
    my (undef, undef, $pfcmd_mode, undef, $pfcmd_owner, $pfcmd_group) = stat($bin_dir . "/pfcmd");
    if (!($pfcmd_mode & S_ISUID && $pfcmd_mode & S_ISGID)) {
        add_problem( $FATAL, "pfcmd needs setuid and setgid bit set to run properly. Fix with chmod ug+s pfcmd" );
    }
    # pfcmd needs to be owned by root (owner id 0 / group id 0) 
    if ($pfcmd_owner || $pfcmd_group) {
        add_problem( $FATAL, "pfcmd needs to be owned by root. Fix with chown root:root pfcmd" );
    }

    # Disabled because it was causing too many false positives 
    # pfcmd (setuid root) changes ownership to root all the time
    ## owner must be pf otherwise we can't modify configuration
    ## only a warning because pf can still run, it's the config we can't change (friendlier cluster failover handling)
    #my @configuration_files = qw(
    #    floating_network_devices.conf networks.conf pf.conf switches.conf violations.conf
    #);
    #foreach my $conf_file (@configuration_files) {
    #    # if file doesn't exist it is created correctly so no need to complain
    #    next if (!-f $conf_dir . '/' . $conf_file);
    #
    #    add_problem( $WARN, "$conf_file must be owned by user pf. Fix with chown pf $conf_dir/$conf_file" )
    #        unless (getpwuid((stat($conf_dir . '/' . $conf_file))[4]) eq 'pf');
    #}

    # log owner must be pf otherwise apache or pf daemons won't start
    my @important_log_files = qw(
        access_log error_log admin_access_log admin_error_log
        packetfence.log
    );
    foreach my $log_file (@important_log_files) {
        # if log doesn't exist it is created correctly so no need to complain
        next if (!-f $log_dir . '/' . $log_file);

        add_problem( $FATAL, "$log_file must be owned by user pf. Fix with chown pf -R logs/" )
            unless (getpwuid((stat($log_dir . '/' . $log_file))[4]) eq 'pf');
    }
}

=item apache

Apache related tests

=cut
sub apache {

    # we dynamically adjust apache's configuration based on total system memory
    # we will first here test if we can figure it out
    my $total_ram = get_total_system_memory();
    if (!defined($total_ram)) {
        add_problem( 
            $WARN, 
            "Unable to find out how much system memory is available. "
            . "We'll assume you have 2 Gigabyte. "
            . "Please report an issue."
        );
    }

    # Apache PerlPostConfigRequire scripts *must* compile otherwise apache startup silently fails
    my $captive_portal = pf_run("perl -c $lib_dir/pf/web/captiveportal_modperl_require.pl 2>&1");
    if (!defined($captive_portal) || $captive_portal !~ /syntax OK$/) {
        add_problem( 
            $FATAL, "Apache will fail to start! $lib_dir/pf/web/captiveportal_modperl_require.pl doesn't compile"
        );
    }
    my $back_end = pf_run("perl -c $lib_dir/pf/web/backend_modperl_require.pl 2>&1");
    if (!defined($back_end) || $back_end !~ /syntax OK$/) {
        add_problem( 
            $FATAL, "Apache will fail to start! $lib_dir/pf/web/backend_modperl_require.pl doesn't compile"
        );
    }
}

=item violations

Checking for violations configurations

=cut
sub violations {
    my %violations_conf;
    tie %violations_conf, 'Config::IniFiles', ( -file => "$conf_dir/violations.conf" );
    my @errors = @Config::IniFiles::errors;
    if ( scalar(@errors) ) {
        add_problem( $FATAL, "Error reading violations.conf");
    }

    my %violations = pf::services::class_set_defaults(%violations_conf);    

    my $deprecated_disable_seen = $FALSE;
    foreach my $violation ( keys %violations ) {

        # parse triggers if they exist
        if ( defined $violations{$violation}{'trigger'} ) {
            try { 
                # TODO we are parsing triggers both on checkup and when we parse the configuration on startup
                # we probably can do something smarter here (but can't find right maintenance / efficiency balance now)
                parse_triggers($violations{$violation}{'trigger'});
            } catch {
                add_problem($WARN, "Violation $violation is ignored: $_");
            };
        }

        if ( defined $violations{$violation}{'disable'} ) {
            $deprecated_disable_seen = $TRUE;
        }
    }

    if ($deprecated_disable_seen) {
        add_problem( $FATAL,
            "violations.conf's disable parameter is deprecated in favor of enabled. " . 
            "Make sure to update your configuration. Read UPGRADE for details and an upgrade script."
        );
    }
}

=item switches

Checking for switches configurations

=cut
sub switches {
    my %switches_conf;
    tie %switches_conf, 'Config::IniFiles', ( -file => "$conf_dir/switches.conf" );
    
    my @errors = @Config::IniFiles::errors;
    if ( scalar(@errors) ) {
        add_problem( $FATAL, "switches.conf | Error reading switches.conf" );
    }

    # remove trailing whitespaces
    foreach my $section ( tied(%switches_conf)->Sections ) {
        foreach my $key ( keys %{ $switches_conf{$section} } ) {
            $switches_conf{$section}{$key} =~ s/\s+$//;
        }
    }

    foreach my $section ( keys %switches_conf ) {
        # skip default switch parameters
        next if ( $section =~ /^default$/i ); 
        
        # validate that switches are not duplicated (we check for type and mode specifically) fixes #766
        if ( ref($switches_conf{$section}{'type'}) eq 'ARRAY' || ref($switches_conf{$section}{'mode'}) eq 'ARRAY' ) {
            add_problem( $WARN, "switches.conf | Error around $section Did you define the same switch twice?" );
        }

        # check type
        my $type = "pf::SNMP::" . ( $switches_conf{$section}{'type'} || $switches_conf{'default'}{'type'} );
        if ( !$type->require() ) {
            add_problem( $WARN, "switches.conf | Switch type ($type) is invalid for switch $section" );
        }

        # check for valid switch IP
        if ( !valid_ip($section) ) {
            add_problem( $WARN, "switches.conf | Switch IP is invalid for switch $section" );
        }

        # check SNMP version
        my $SNMPVersion = ( $switches_conf{$section}{'SNMPVersion'}
                || $switches_conf{$section}{'version'}
                || $switches_conf{'default'}{'SNMPVersion'}
                || $switches_conf{'default'}{'version'} );
        if ( !defined($SNMPVersion) ) {
            add_problem( $WARN, "switches.conf | Switch SNMP version is missing for switch $section"
                    . "Please provide one specific to the switch or in default." );
        } elsif ( !($SNMPVersion =~ /^1|2c|3$/) ) {
            add_problem( $WARN, "switches.conf | Switch SNMP version ($SNMPVersion) is invalid for switch $section" );
        }

        # check SNMP Trap version
        my $SNMPVersionTrap = ($switches_conf{$section}{'SNMPVersionTrap'} 
                || $switches_conf{'default'}{'SNMPVersionTrap'});
        if (!defined($SNMPVersionTrap)) {
            add_problem( $WARN, "switches.conf | Switch SNMP Trap version is missing for switch $section"
                    . "Please provide one specific to the switch or in default." );
        } elsif ( !( $SNMPVersionTrap =~ /^1|2c|3$/ ) ) {
            add_problem( $WARN, "switches.conf | Switch SNMP Trap version ($SNMPVersionTrap) is invalid "
                    . "for switch $section" );
        } elsif ( $SNMPVersionTrap =~ /^3$/ ) {
            # mandatory SNMPv3 traps parameters
            foreach (qw(
                SNMPUserNameTrap SNMPEngineID 
                SNMPAuthProtocolTrap SNMPAuthPasswordTrap 
                SNMPPrivProtocolTrap SNMPPrivPasswordTrap
            )) {
                add_problem( $WARN, "switches.conf | $_ is missing for switch $section" )
                    if (!defined($switches_conf{$section}{$_}));
            }
        }

        # check uplink
        my $uplink = $switches_conf{$section}{'uplink'} || $switches_conf{'default'}{'uplink'};
        if ( (!defined($uplink)) || (( lc($uplink) ne 'dynamic' ) && (!( $uplink =~ /(\d+,)*\d+/ ))) ) {
            add_problem( $WARN, "switches.conf | Switch uplink is invalid for switch $section" );
        }

        # check mode
        my @valid_switch_modes = ( 'testing', 'ignore', 'production', 'registration', 'discovery' );
        my $mode = $switches_conf{$section}{'mode'} || $switches_conf{'default'}{'mode'};
        if ( !grep( { lc($_) eq lc($mode) } @valid_switch_modes ) ) {
            add_problem( $WARN, "switches.conf | Switch mode ($mode) is invalid for switch $section" );
        }

        # check role
        my $roles = $switches_conf{$section}{'roles'} || $switches_conf{'default'}{'roles'};
        # if it's not empty it must be in the <cat1>=<role1>;<cat2>=<role2>;... format
        if ( defined($roles) && $roles !~ /^\s*$/ && $roles !~ /
            ^\w+=\w+         # at least one word=word
            (;\w+=\w+)*      # maybe more word=word in that case they must be prefixed by ;
            ;?               # optional ending ;
            $/x ) {
            add_problem(
                $WARN, 
                "switches.conf | Roles parameter ($roles) is badly formatted for switch $section. "
                . "It should be: <category_name1>=<controller_role1>;<category_name2>=<controller_role2>;..."
            );
        }

    }
}

=item billing

Validation related to the billing engine feature.

=cut
sub billing {
    # Check if the configuration provided payment gateway is instanciable
    my $payment_gw = 'pf::billing::gateway::' . lc($Config{'billing'}{'gateway'});

    try {
        eval "use $payment_gw;";
        die($@) if ($@);
        my $gw = $payment_gw->new();

        if (!defined($gw->VERSION())) { 
            add_problem($FATAL, "Payment gateway module $payment_gw is enabled and its VERSION is not defined.");
        } 
        elsif ($BILLING_API_LEVEL > $gw->VERSION()) { 
            add_problem( $FATAL,
                "Payment gateway module $payment_gw is enabled and is not at the correct API level. " .
                "Did you read the UPGRADE document?"
            );
        }
    } catch {
        chomp($_);
        add_problem( $FATAL, "Billing: Incorrect payment gateway declared in pf.conf: $_" );
    };
}

=item unsupported

Feature that we know don't work under certain circumstances (or other features activated)

=cut
sub unsupported {

    # SMS confirmation doesn't work with pre-registration
    # This was not implemented due to a time constraint. We can fix it.
    if (isenabled($Config{'guests_self_registration'}{'preregistration'}) && $guest_self_registration{$SELFREG_MODE_SMS}) {
        add_problem( $WARN, "Registering by SMS doesn't work with preregistration enabled." );
    }
}

=back

=head1 AUTHOR

Olivier Bilodeau <obilodeau@inverse.ca>

Francois Gaudreault <fgaudreault@inverse.ca>

Derek Wuelfrath <dwuelfrath@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2011-2012 Inverse inc.

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
# vim: set tabstop=4:
# vim: set autoindent:
# vim: set expandtab:
# vim: set backspace=indent,eol,start:
