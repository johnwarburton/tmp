class puppet_client {

    include puppet_client::puppet_client_info

    if ($::puppet_pkg_version == '') {

        # If there is no NC parameter for puppet_pkg_version then lookup hieradata
        if (tagged('puppet_server')) {
            $puppet_pkg_version = hiera('puppet_server_version')
        }
        else {
            $puppet_pkg_version = hiera('puppet_version')
        }

        # One day we will be on one version of ruby everywhere, until then enjoy getting your head
        # around this logic
        # The version of Ruby depends on the version of Puppet. E.g. 3.7.0 requires >= Ruby 1.9.3
        if ($::osfamily == 'RedHat') {

            if versioncmp($::operatingsystemrelease, 6) > 0 {
                $yum_ruby_version = hiera('ruby_version_rhel6')
            }
            else {
                $yum_ruby_version = hiera('ruby_version')
            }

            $ruby_version = regsubst($yum_ruby_version, '_', '-', 'G')
        }
        elsif ($::osfamily == 'Solaris') {
            $ruby_version = hiera('ruby_version_solaris')
        }
        else {
            fail('OS not supported. How did you make it this far?')
        }

    }
    elsif versioncmp($::puppet_pkg_version, '3') > 0 {
        # elsif the version of puppet_pkg_version is higher than 3
        # assume solaris and rhel are using the same ruby 1.9.3 version
        # versionlock.list looks for yum_ruby_version

        $yum_ruby_version = hiera('puppet3_ruby_version')
        $ruby_version = regsubst($yum_ruby_version, '_', '-', 'G')
    }
    else {
        # We can quickly run into a situation where we try and code for every eventuality
        # If a puppet server is specifically defined as 2.7.26 or 2.6.18, then die.
        # I don't want to write in crap logic that will soon be redundant and serve no other
        # purpose than to confuse people
            if versioncmp($::operatingsystemrelease, 6) > 0 {
                $yum_ruby_version = hiera('ruby_version_rhel6')
            }
            else {
              $yum_ruby_version = hiera('ruby_version')
            }
            $ruby_version = regsubst($yum_ruby_version, '_', '-', 'G')
        notice('NC parameter "puppet_pkg_version" defined unnecessarily. Please remove it')
    }

    # We want to reference the semantic version every now and again e.g. 1.9.3
    $ruby_semantic_version = regsubst($ruby_version,'^([0-9]+\.[0-9]+\.[0-9])(.*)$','\1')

    # Testing mcollective

    # You have to have the ruby_version defined BEFORE you include mcollective
    # because dirty secret about puppet - order is important with variables
    # and includes
    if ($environment =~ /^(lab|L.*)$|eng/) {
        include mcollective
    }

    # Support scripts
    #
    file { '/opt/local/sbin/run-puppet.sh':
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => 'puppet:///modules/puppet_client/opt/local/sbin/run-puppet.sh',
    }

    file { '/opt/local/sbin/puppet-register.sh':
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => 'puppet:///modules/puppet_client/opt/local/sbin/puppet-register.sh',
    }

    file { '/opt/local/sbin/puppet-register-secure.sh':
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => 'puppet:///modules/puppet_client/opt/local/sbin/puppet-register-secure.sh',
    }

    file { '/opt/local/bin/puppet_file_bucket.sh':
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => 'puppet:///modules/puppet_client/opt/local/bin/puppet_file_bucket.sh',
    }

    file { '/opt/local/etc/puppetenv':
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => 'puppet:///modules/puppet_client/opt/local/etc/puppetenv',
    }

    file { '/var/log/puppet_client':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0775',
    }

    file { '/opt/local/puppet-modules':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
    }

    # Only install BLKrubygems if the version of Ruby is less that 1.9.3
    if versioncmp($ruby_semantic_version, '1.9.3') < 0 {
        common::local_package {'BLKrubygems':
            version       => '1.3.6',
            graft         => 'yes',
            graft_chkfile => 'bin/gem',
        }
    }

    # we need in on all puppet servers no matter its OS
    if ($::osfamily == 'RedHat') {
        if (tagged('puppet_server')) {
            $puppet_lvm_version = '0.3.1'
        } elsif ($::puppet_lvm_version == '') {
            $puppet_lvm_version = hiera('puppet_lvm_version')
        }

        common::local_package {'BLKpuppetlabs-lvm':
            version => $puppet_lvm_version,
            graft   => 'no',
            require => File[
                '/opt/local/puppet-modules',
                '/etc/yum/pluginconf.d/versionlock.list'
            ],
        }
    }

    if ((tagged('puppet_server') or tagged('jenkins_server')) and ($::osfamily == 'RedHat')) {
        common::local_package {'BLKpuppetlabs-stdlib':
            version => '4.5.1',
            graft   => 'no',
            require => File['/opt/local/puppet-modules'],
        }
    }

    if ($environment =~ /^(lab|L.*)$/) {
        # Bit more often in lab, before other envts (may help catch errors?)
        $puppet_run_hours = [0,6,12]
    } else {
        $puppet_run_hours = [6]
    }

    # Report back to the dashboard pending changes. Frequency is dependant
    # on the Environment
    # Non lab/eng servers run this at around 6am and 6pm system time
    # rename cron job
    cron {'puppet client':
        ensure  => absent,
        command => '/opt/local/sbin/run-puppet.sh --noop --show_diff true --verbose >> /var/log/puppet_client/puppet_client.log 2>&1',
    }

    # We only want to run full Puppet run for McMorgan non-dbs servers
    if (($::client == 'mcm') and ! tagged('sybase_server')) {
        $puppet_client_run = 'puppet client full OP'
        $puppet_client_cmd = '/opt/local/sbin/run-puppet.sh --show_diff true --verbose >> /var/log/puppet_client/puppet_client.log 2>&1'
    }
    else {
        $puppet_client_run = 'puppet client noop'
        $puppet_client_cmd = '/opt/local/sbin/run-puppet.sh --noop --show_diff true --verbose >> /var/log/puppet_client/puppet_client.log 2>&1'
    }

# ... .... ....

    # need to update it there before we upgrade (if needed)
    # here
    if ($::osfamily == 'RedHat') {
        $puppet_requires = [  Common::Local_package['BLKfacter'],
                              File['/etc/yum/pluginconf.d/versionlock.list'], ]
        $libff_graft_chkfile = 'lib64/libffi.so'
    }
    else {
        $puppet_requires = [ Common::Local_package['BLKfacter'], ]
        $libff_graft_chkfile = 'lib/libffi.so'
    }

    # only install BLKlibffi and BLKlibyaml on hosts that have Ruby 1.9 or are compile_servers
    if ( versioncmp($ruby_version, '1.9.3') >= 0 or tagged('compile_server')) {
        common::local_package {'BLKlibffi':
            version       => '3.1',
            graft         => 'yes',
            graft_chkfile => $libff_graft_chkfile,
            require       => $ruby_requires,
        }

        common::local_package {'BLKlibyaml':
            version       => '0.1.5',
            graft         => 'yes',
            graft_chkfile => 'include/yaml.h',
            require       => $ruby_requires,
        }
    }

    common::local_package { 'BLKpuppet':
        version       => $puppet_pkg_version,
        graft         => 'yes',
        graft_chkfile => 'bin/puppet',
        require       => $puppet_requires,
    }

    if ($::facter_pkg_version == '') {
        $facter_pkg_version = hiera('puppet_facter_version') # final 1.6.x release
    }

    $facter_requires = $::osfamily ? {
        redhat  => File['/etc/yum/pluginconf.d/versionlock.list'],
        default => undef,
    }

    common::local_package { 'BLKfacter':
        version       => $facter_pkg_version,
        graft         => 'yes',
        graft_chkfile => 'bin/facter',
        require       => $facter_requires,
    }

    common::local_package {'BLKgraft':
        version       => '2.4',
        graft         => 'yes',
        graft_chkfile => 'bin/graft',
    }
}





