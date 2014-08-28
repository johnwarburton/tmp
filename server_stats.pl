#!/usr/bin/perl
#
# Description: update server_stats table in osbuild_stats database
#
#      SVN ID: $Id: server_stats.pl 181526 2014-05-05 02:54:25Z warbjoh $
#
#     SVN Rev: $Rev: 181526 $
#
#  SVN Source: $HeadURL: https://puppet-svn.bfm.com/svn-repo/puppet/tags/prod_blk/modules/osbuild_stats/files/opt/local/sbin/server_stats.pl $
#
#       Notes: *
#              *
#
use strict;
use warnings;

use DBI;
use DBD::mysql;

my $platform   = "mysql";
my $db         = "osbuild_stats";
my $host       = "localhost";
my $port       = "3306";
my $stats_user = "stats_user";
my $stats_pass = "stats";
my $dsn = "DBI:mysql:database=$db;host=$host;port=$port;mysql_multi_statements=1";

my (
    $hostname,          $serial_no,    $geo,   $asset_loc,  $aladdin_client,
    $declared_function, $server_state, $os_nm, $os_release, $kernel_patch_no,
    $architecture_nm, $cpu_count, $cpu_speed_mhz, $ram_amt_mb, $swap_amt_mb,
    $extract_dt,      $comments
);

my ( $date, $total, $linux, $solaris,       $other,      $active,     $estate_memory, $maint );
my ( %DUMP, @dumps, $dump,  $server_insert, @have_dates, $have_dates, $query );

my $inventory_dump = "/local/puppet-databases/dashboard-dump/inventory";

opendir( DUMP_DIR, $inventory_dump )
  or die "Cannot open $inventory_dump for readdir: $!\n";
@dumps = grep { ( !/^\./ ) } readdir(DUMP_DIR);
closedir(DUMP_DIR);

#
# Find out what dates we already have data for and filter out
#

$query = qq{
    select date from server_stats;
};
my $dbh = DBI->connect( $dsn, $stats_user, $stats_pass )
  or die "Could not connect:\n" . DBI->errstr;
my $query_handle = $dbh->prepare($query)
  or die "Can't prepare statement: $DBI::errstr";
$query_handle->execute();
# http://www.perlmonks.org/?node=DBI%20Recipes#fetching
@have_dates = @{ $dbh->selectcol_arrayref($query) };
$query_handle->finish;
$dbh->disconnect;

@have_dates = map { $_ =~ s/-//g; $_ } @have_dates;
# turn into a regexp to grep against
$have_dates = join( '|', @have_dates );
@dumps = grep { !/$have_dates/ } @dumps;

foreach $dump ( sort @dumps ) {
    $date = $dump;
    $date =~ s/invhostinfo.all.(\d\d\d\d)(\d\d)(\d\d).gz/$1-$2-$3/;

    undef %DUMP;
    $DUMP{'other'} = 0;
    $DUMP{'virtualized'} = 0;

    open( DUMP, "zcat $inventory_dump/$dump |" )
      or die "Cannot open $inventory_dump/$dump for reading: $!\n";
    while (<DUMP>) {

        (
            $hostname, $serial_no, $geo, $asset_loc, $aladdin_client,
            $declared_function, $server_state, $os_nm, $os_release,
            $kernel_patch_no,
            $architecture_nm, $cpu_count, $cpu_speed_mhz, $ram_amt_mb,
            $swap_amt_mb,
            $extract_dt, $comments
        ) = split(',');

        next if ( $server_state !~ /m|a/ );
        next if ( !defined($kernel_patch_no) );      # MnM stuff up
        next if ( $kernel_patch_no =~ /^$/ );        # MnM stuff up
        next if ( $kernel_patch_no eq "v1.9.2" );    # console servers
        next if ( $os_release =~ /UNKNOWN/ );
        next if ( $kernel_patch_no =~ /UNKNOWN/ );
        next if ( $hostname =~ /rdcftp/ );           # tumbleweed
        next if ( $hostname =~ /^was[_|-]/ );
        next if ( $hostname =~ /_CNFLCT_/ );

        $DUMP{'total'}++;
        $DUMP{'active'}++ if ( $server_state eq "a" );
        $DUMP{'maint'}++  if ( $server_state eq "m" );
        if ( $os_nm =~ /SunOS|Solaris/i ) {
            $DUMP{'solaris'}++;
        }
        elsif ( $os_nm =~ /Linux/i ) {
            $DUMP{'linux'}++;
        }
        else {
            $DUMP{'other'}++;
        }
        $DUMP{'estate_memory'} += $ram_amt_mb;

        if (defined($architecture_nm)) {
            # some days there is nothing but nulls due to data gathering issues
            $DUMP{'virtualized'}++ if ($architecture_nm =~ /vmware|RHEV Hypervisor|ldom/i);
        }
    }

    $total   = $DUMP{'total'};
    $linux   = $DUMP{'linux'};
    $solaris = $DUMP{'solaris'};
    $other   = $DUMP{'other'};
    $active  = $DUMP{'active'};
    $maint   = $DUMP{'maint'};
    $estate_memory   = $DUMP{'estate_memory'};

    $server_insert = qq{
        INSERT INTO server_stats (date, total, linux, solaris, other, active, maint, estate_memory, virtualized)
        VALUES ('$date', '$total', '$linux', '$solaris', '$other', '$active', '$maint', '$estate_memory', $DUMP{'virtualized'});
    };
    # add an entry into the change table
    dbInsert($server_insert);

    close(DUMP);
}

sub dbInsert {
    my ($query) = @_;
    my $dbh = DBI->connect( $dsn, $stats_user, $stats_pass )
      or die "Could not connect:\n" . DBI->errstr;
    $dbh->do($query);
    $dbh->disconnect;
}
