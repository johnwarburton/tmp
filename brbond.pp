#
# Description: Linux network bonding of bridges
#
#      SVN ID: $Id: brbond.pp 293669 2015-06-11 02:37:19Z warbjoh $
#
#     SVN Rev: $Rev: 293669 $
#
#  SVN Source: $HeadURL: https://puppet-svn.bfm.com/svn-repo/puppet/branches/UX-4477/modules/base/manifests/brbond.pp $
#
#       Notes: * The server needs to have the bond_pair
#                parameter set in the node classifier, a colon separated list
#                of the bond name and two NICs to be used for bonding
#              * All bonds are configured with options: "miimon=100 mode=active-backup"
#                /usr/share/doc/iputils-20071127/README.bonding
#              * Warning - this only works for one bond pair for now
#              * https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/s2-networkscripts-interfaces_network-bridge.html
#              * Use br-bond0 http://www.slideshare.net/vbannai/neutron-hybrid-openstack-hk
#
class base::brbond {

    $bond = inline_template('<%= @brbond_pair.split(":")[0] %>')
    $if1  = inline_template('<%= @brbond_pair.split(":")[1] %>')
    $if2  = inline_template('<%= @brbond_pair.split(":")[2] %>')

    if (tagged(dlp_server) and (versioncmp($::operatingsystemrelease, 6) > 0)) {
        file {"/etc/sysconfig/network-scripts/ifcfg-${if1}":
            owner   => 'root',
            group   => 'root',
            mode    => '0644',
            content => "DEVICE=${if1}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\nETHTOOL_OPTS=\"-K ${if1} tx off rx off\"\n",
        }

        file {"/etc/sysconfig/network-scripts/ifcfg-${if2}":
            owner   => 'root',
            group   => 'root',
            mode    => '0644',
            content => "DEVICE=${if2}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\nETHTOOL_OPTS=\"-K ${if2} tx off rx off\"\n",
        }
    }
    else {
        file {"/etc/sysconfig/network-scripts/ifcfg-${if1}":
            owner   => 'root',
            group   => 'root',
            mode    => '0644',
            content => "DEVICE=${if1}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\n",
        }

        file {"/etc/sysconfig/network-scripts/ifcfg-${if2}":
            owner   => 'root',
            group   => 'root',
            mode    => '0644',
            content => "DEVICE=${if2}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\n",
        }
    }

    # variables of variables
    # https://blog.kumina.nl/2010/09/puppet-tipstricks-variable-variables/
    #$iface_addr_ptr = "ipaddress_${if1}"
    #$iface_addr = inline_template("<%= scope.lookupvar(iface_addr_ptr) %>")
    #$iface_mask_ptr = "netmask_${if1}"
    #$iface_mask = inline_template("<%= scope.lookupvar(iface_mask_ptr) %>")

    file {"/etc/sysconfig/network-scripts/ifcfg-${bond}":
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "DEVICE=${bond}\nBOOTPROTO=static\nONBOOT=yes\nUSERCTL=no\nBRIDGE=br-${bond}\n",
    }

    file {"/etc/sysconfig/network-scripts/ifcfg-br-${bond}":
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "DEVICE=br-${bond}\nBOOTPROTO=static\nONBOOT=yes\nTYPE=Bridge\nIPADDR=${::ipaddress}\nNETMASK=${::netmask}\nGATEWAY=${::default_gw}\nUSERCTL=no\n",
    }

    file {'/etc/modprobe.d/bonding.conf':
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "alias ${bond} bonding\noptions bonding miimon=100 mode=active-backup\n",
    }

}
#PUPPET_LINT
