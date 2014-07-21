warbjoh@labnadm011% cat modules/common/manifests/defines/local_package.pp
#
# Description: Wrapper for grafting BLK packages in Solaris & Linux
#
#      SVN ID: $Id: local_package.pp 175460 2014-04-11 17:48:09Z talbert $
#
#     SVN Rev: $Rev: 175460 $
#
#  SVN Source: $HeadURL: https://puppet-svn.bfm.com/svn-repo/puppet/trunk/modules/common/manifests/defines/local_package.pp $
#
#       Notes: * Inspired by http://groups.google.com/group/puppet-users/msg/38d3dc9e85bdecd0?dmode=source
#              * Default subdirectory to look in is BLK
#              * Renamed from graft_pkgadd
#
define local_package($version, $package_name='', $graft='yes', $graft_to='', $graft_chkfile='', $response='', $admin='/var/sadm/install/admin/puppet', $subdir='BLK', $ensure='') {

    # This allows you to install (not graft) more than one version of a Solaris package.
    if ($package_name != '') {
        $package = $package_name
    }
    else {
        $package = $name
    }


    $longvers = regsubst($version, '\.', '-', 'G')

    # Use the lab pkg repo for individual's environments
    if ($environment =~ /^L/) {
        $pkg_env = 'lab'
    }
    else {
        $pkg_env = $environment
    }

    if ($::osfamily == 'Solaris') {

        $repourl = "http://${servername}/packages/${pkg_env}/${::kernel}/${subdir}"

        if ($package =~ /^BLK/) {
            $filename = "${package}-${longvers}-solaris10.${::hardwareisa}.pkg"
        }
        else {
            $filename = "${package}-${version}.sparc.pkg"
        }

        # pkgadd does not support response files when using an http repo (SR 72897782)
        # so we have to copy the file locally, and run the pkgadd from there
        if ($response != '') {
            $pkgrepo = '/var/tmp'

            # These facts are set by common/lib/facter/pkgs_facts.rb
            # use $response_* in the variable name as we're doing
            # a similar thing in graft.pp
            $response_pkg_name = "pkg_${package}"
            $response_current_vers = inline_template('<%= scope.lookupvar(response_pkg_name.downcase) %>')
            #notify {"graft_pkgadd: $package $version $response_pkg_name $response_current_vers": }

            # If the package is alerady installed, and the temp pkg file exists
            # then delete it

            case $version {
                $response_current_vers : { $filename_ensure = absent }
                default : { $filename_ensure = present }
            }

            file {"/var/tmp/${filename}":
                ensure  => $filename_ensure,
                # we don't want to backup pkg files to the file bucket
                backup  => false,
                require => Package["pkgadd ${package}-${version}"],
            }

            #
            # Wget -O will always create a file - and empty if it fails - no
            # matter what. Since the existence of the file is what we are
            # using for idempotency, we need to make sure the file is not
            # zero length - hence the "! -s" string
            # http://marc.info/?t=113748860400004
            #
            if ($version != $response_current_vers) {
                exec {"localpkg_${package}":
                    path    => '/usr/bin:/usr/sbin:/bin',
                    command => "/opt/local/bin/wget -q -O /var/tmp/${filename} ${repourl}/${filename}; \
                                   [ ! -s /var/tmp/${filename} ] && /bin/rm -f /var/tmp/${filename} || true",
                    creates => "/var/tmp/${filename}",
                    before  => Package["pkgadd ${package}-${version}"],
                    require => Local_package['BLKwget'],
                }
            }
        }
        else {
            $pkgrepo = $repourl
        }

        case $package {
            /^BLK/ : { $pkgadd_name = "${package}-${longvers}"}
            default: { $pkgadd_name = $package }
        }

        case $package {
            /[a-z\/]/: { $pkgadd_adminfile = $admin }
            default:   { $pkgadd_adminfile = '/var/sadm/install/admin/puppet' }
        }

        case $response {
            /[a-z]/: { $pkgadd_responsefile = $response }
            default: { $pkgadd_responsefile = undef }
        }

        package{"pkgadd ${package}-${version}":
            source       => "${pkgrepo}/${filename}",
            name         => $pkgadd_name,
            adminfile    => $pkgadd_adminfile,
            responsefile => $pkgadd_responsefile,
            require      => File[$admin],
        }

        if ($graft == 'yes') {
            if ($graft_chkfile == '') {
                fail('common/manifests/defines/pkgadd.pp: graft set to yes, but graft_chkfile empty')
            }

            # assume that graftable packages start with BLK which
            # we need to chomp
            $graft_pkg_name = regsubst($package, 'BLK', '')
            graft {"graft ${graft_pkg_name}-${version}":
                pkg      => $graft_pkg_name,
                version  => $version,
                action   => install,
                chkfile  => $graft_chkfile,
                graft_to => $graft_to,
                require  => Package["pkgadd ${package}-${version}"],
            }
        }
    }

    elsif (($::osfamily == 'RedHat') and ($ensure == 'absent')) {

        $graft_pkg_name = regsubst($package, 'BLK', '')

        exec {"ungraft ${package}-${version}":
            path    => '/bin:/sbin:/usr/bin:/usr/sbin:/opt/local/bin',
            command => "graft -D -d ${graft_pkg_name}-${version}",
            onlyif  => "test -d /opt/local/pkgs/${graft_pkg_name}-${version}",
        }

        exec {"yum erase ${package}":
            path    => '/bin:/sbin:/usr/bin:/usr/sbin',
            command => "yum erase ${package} -y",
            # no need to version fix the $current_pkg_ver (ie convert '-' to '_' in the version)
            onlyif  => "rpm -q ${package}-${version}-1.el${::operatingsystemmajor}",
            require => Exec["ungraft ${package}-${version}"],
        }
    }

    elsif ($::osfamily == 'RedHat') {

        if ($package =~ /^BLK/) {
            # some packages have '-' in the version (ie BLKruby, BLKbind, BLKdhcp)
            # this causes a mismatch as yum is expecting an underscore '_'
            $remove_hyphens = regsubst($version, '-', '_', 'G')
            $versionfix = "${remove_hyphens}-1.el${::operatingsystemmajor}"
        }
        else {
            $versionfix = $version
        }

        # ugly hack - trying to match how Puppet checks packages
        # /bin/rpm -q BLKfacter --nosignature --nodigest --qf '%{NAME} %|EPOCH?{%{EPOCH}}:{0}| %{VERSION} %{RELEASE} %{ARCH}'
        case $version {
            /[0-9]/: { $yum_ensure = $versionfix }
            default: { $yum_ensure = latest }
        }

        package{"yum ${package}":

            # Yum provider using "version-release" to validate installation.
            # http://projects.puppetlabs.com/issues/3538

            ensure  => $yum_ensure,
            name    => $package,
            require =>  [ Yumrepo['blk-3rd-party'], ],
        }

        if ($graft == 'yes') {

            # assume that graftable packages start with BLK which
            # we need to chomp
            $graft_pkg_name = regsubst($package, 'BLK', '')

            $pkg_name = "pkg_${graft_pkg_name}"

            if ($graft_chkfile == '') {
                fail('common/manifests/defines/pkgadd.pp: graft set to yes, but graft_chkfile empty')
            }

            # problem with using eval (eg when package is BLKapache-infra)
            # it only sees BLKapache - drops the '-infra'
            # tried to quote but doesn't seem to work
            #$current_pkg_ver = inline_template("<%= eval(%{pkg_#{graft_pkg_name}}) %>")

            # eg (pkg_blkruby: 1.8.7_p249-1.el5; pkg_blkdhcp: 4.2.3_P2-1.el6)
            # we just need the version stripped out but take note of packages
            # with '_' in the version number.
            $current_pkg_ver = inline_template('<%= scope.lookupvar(pkg_name) %>')

            # On Linux, using 'ensure => latest' for package install will remove
            # the old version. In Solaris, previous version is not removed. There's quite a difference
            # in solaris/linux packages. Solaris packages have version number part of the package name.
            # In linux, it's just the package name. The version (and release) number is provided by Yum.
            # We need to 'ungraft' the old version first so we can properly 'graft' the new version

            # bug with scope lookup http://projects.puppetlabs.com/issues/8707
            if (($version != $current_pkg_ver) and ($current_pkg_ver != 'undefined')) {
            #if (($version != $current_pkg_ver) and ($current_pkg_ver != "")) {
                exec {"ungraft ${package}-${current_pkg_ver}":
                    path    => '/bin:/sbin:/usr/bin:/usr/sbin:/opt/local/bin',
                    command => "graft -D -d ${graft_pkg_name}-${current_pkg_ver}",
                    # this needs to happen before we install the latest package version
                    before  => Package["yum ${package}"],
                }

                # can't have duplicate package resource
                exec {"yum erase ${package}":
                    path    => '/bin:/sbin:/usr/bin:/usr/sbin',
                    command => "yum erase ${package} -y",
                    # no need to version fix the $current_pkg_ver (ie convert '-' to '_' in the version)
                    onlyif  => "rpm -q ${package}-${current_pkg_ver}-1.el${::operatingsystemmajor}",
                    require => Exec["ungraft ${package}-${current_pkg_ver}"],
                    before  => Package["yum ${package}"],
                }
            }

            # packages with '-' in the version create directories with '-' when installed
            graft {"graft ${graft_pkg_name}-${version}":
                pkg      => $graft_pkg_name,
                version  => $version,
                action   => install,
                chkfile  => $graft_chkfile,
                graft_to => $graft_to,
                require  => Package["yum ${package}"],
            }
        }
    }
}
