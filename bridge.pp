#
# Description: Linux network bonding of bridges
#
#      SVN ID: $Id: bridge.pp 304420 2015-07-20 12:01:55Z warbjoh $
#
#     SVN Rev: $Rev: 304420 $
#
#  SVN Source: $HeadURL: https://puppet-svn.bfm.com/svn-repo/puppet/branches/UX-4477/modules/blade_project/manifests/bridge.pp $
#
#       Notes: * The server needs to have the bond_pair
#                parameter set in the node classifier, a colon separated list
class blade_project::bridge {

    $bond = inline_template('<%= @brbond_pair.split(":")[0] %>')
    $if1  = inline_template('<%= @brbond_pair.split(":")[1] %>')
    $if2  = inline_template('<%= @brbond_pair.split(":")[2] %>')

    # variables of variables
    # https://blog.kumina.nl/2010/09/puppet-tipstricks-variable-variables/
    $if1_hwaddr_ptr = "macaddress_${if1}"
    $if1_hwaddr = inline_template('<%= scope.lookupvar(if1_hwaddr_ptr) %>')
    $if2_hwaddr_ptr = "macaddress_${if2}"
    $if2_hwaddr = inline_template('<%= scope.lookupvar(if2_hwaddr_ptr) %>')

    file {"/etc/sysconfig/network-scripts/ifcfg-${if1}":
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "DEVICE=${if1}\nHWADDR=${if1_hwaddr}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\n",
    }

    file {"/etc/sysconfig/network-scripts/ifcfg-${if2}":
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "DEVICE=${if2}\nHWADDR=${if2_hwaddr}\nBOOTPROTO=none\nONBOOT=yes\nMASTER=${bond}\nSLAVE=yes\nUSERCTL=no\n",
    }

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
        content => "DEVICE=br-${bond}\nBOOTPROTO=static\nONBOOT=yes\nTYPE=Bridge\nSTP=off\nDELAY=0\nIPADDR=${blade_project::bridge_address}\nNETMASK=${blade_project::bridge_mask}\nUSERCTL=no\n",
    }

}
#PUPPET_LINT
