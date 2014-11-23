#
# Description: ext_lib class
#
#      SVN ID: $Id: init.pp 240374 2014-11-19 02:34:30Z warbjoh $
#
#     SVN Rev: $Rev: 240374 $
#
#  SVN Source: $HeadURL: https://puppet-svn.bfm.com/svn-repo/puppet/branches/UX-3565/modules/ext_lib/manifests/init.pp $
#
#       Owner: osbuild
#
#       Notes: * Sang Lee drops third party libraries (like openssl
#                and openldap) for JAWS applications Squid/Apache
#                into /local/apps/ext-lib
#              * Sang: "We need to create /local/apps/ext-lib directory
#                and change ownership to release:bfmrel"
#
class ext_lib {

    $openssl_ext_version = '1.0.1-1'
    $openssl_ext_32_URL = "http://${::servername}/packages/3rd_party/JAWS/BLKopenssl-${openssl_ext_version}.el5.i686.tar.bz2"
    $openssl_ext_64_URL = "http://${::servername}/packages/3rd_party/JAWS/BLKopenssl-${openssl_ext_version}.el5.x86_64.tar.bz2"

    exec { "extract BLKopenssl-${openssl_ext_version} tarball":
        path    => '/opt/local/bin:/bin:/sbin:/usr/bin:/usr/sbin',
        user    => 'release',
        cwd     => '/local/apps/ext-lib/lib64',
        command => "wget -T 5 -t 2 -q ${openssl_ext_64_URL} && bzip2 -dc BLKopenssl-${openssl_ext_version}.x86_64.tar.bz2 | tar xf -",
        unless  => "test -d /local/apps/ext-lib/lib64/openssl_${openssl_ext_version}",
        require => [ Common::Local_filesystem['ext-lib'], ],
    }

    exec { "remove BLKopenssl-${openssl_ext_version} tarball":
        path    => '/opt/local/bin:/bin:/sbin:/usr/bin:/usr/sbin',
        user    => 'release',
        cwd     => '/local/apps/ext-lib/lib64',
        command => "rm -f BLKopenssl-${openssl_ext_version}.x86_64.tar.bz2",
        onlyif  => "test -f BLKopenssl-${openssl_ext_version}.x86_64.tar.bz2",
        require => [ Exec["extract BLKopenssl-${openssl_ext_version} tarball"], ],
    }

    common::local_filesystem { ['ext-lib', ]:
        top      => '/local/apps',
        owner    => 'release',
        group    => 'bfmrel',
        mode     => '2775',
        size     => '5G',
    }

    file { ['/local/apps/ext-lib/lib', '/local/apps/ext-lib/lib64', ]:
        ensure   => directory,
        owner    => 'release',
        group    => 'bfmrel',
        mode     => '2775',
    }

}

#PUPPET_LINT
