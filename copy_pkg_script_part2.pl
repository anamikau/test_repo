#! /usr/bin/perl -w
  
use Getopt::Long;
use strict;
use Time::Local;
use File::Compare;
use File::Copy;
use File::stat;
use Getopt::Std;

#===================================================

$SIG{INT} = 'INT_handler';

sub INT_handler {
  my $signame = shift;
  print "Caught signal $signame. Do you want to continue? Y/N\n";
  my $ans=<>;
  if ($ans=~/N/i){
    die "\ncaught SIGNAL $signame. Exiting ...\n";
  }
}


sub check_perm($) {
  my $dir = shift;
  my $perm = `ls -ld $dir | awk '{print \$1}'`;
  chomp($perm);
  if ($perm =~ /drwxrwxr-x/ig) {
    return 1;
  }
  return 0;
}

sub copy_file($$) {
  my $sourcedir = shift;
  my $targetdir = shift;
  my $tgtfile;

  if (!$sourcedir || !$targetdir) {
     print STDERR "Source and targets directories both are required\n";
     return -1;
  }
  print STDERR "source = $sourcedir and target = $targetdir\n";
  opendir(DIR,$sourcedir);
  my @file = readdir(DIR);
  foreach my $i (@file) {
    $tgtfile = $targetdir . "/" . $i;
    print STDERR "copying $i as $tgtfile\n";    
    copy($i, $tgtfile) or return -1;
   }
  return 1;
}

#======================================================
  
my $version = ''; # PBS build version. for example, 12.3.100, 12.0.0
my $buildid = ''; # PBS build id
my $qabnum = ''; # QAB id that needs to be copied
my $ispatch = 0; # if it is a special patch
my $release = ''; # PBS release id. for example, 12.2, 11.0.
my $internal = ''; # QAB location inside internal. for example, PBS-QAB1
my $trynum = 1; # try number inside QAB directory on cvs
my $help = 0;
my $copyscr = "copy.simple_processed.sh"; # name of the copy.simple script
my $incoming_path='';
my $processed_path='';
my $prev_rel='';
my $ip_path = '';
my $qabname = "QAB"; #name of QAB. Default is QAB. For some cases it could be PQAB
my $ipname = "IP";
my $non_jenkin = 1; # making it true by default since jenkins is on hold
my $build_tag;

my $usage = "\n Usage for copy_pkg_script_part2.pl --- \n This will be called by parent script from CVS. This can be called independently with following options.\n\nperl copy_pkg_script_part2.pl -V <PBS build version> -id <PBS build id> -Q <QAB name> -N <QAB number> -R <PBS release id> -P <0|1 to specify if it is a patch> -t <try number of QAB> -IPN <IP name> -I <QAB directory inside incoming> -C <copy script name> -incoming <incoming path> -processed <processed folder path> -prev <path to previous release to compare the package> -ip <path to IP location> -BT <Build tag> -nJ <flag to specify if running non_jenkins build>\n\n Where -P is 0 by default\n-t is 1 as default\n-C is copy-simple-1July2014.sh as default\n-Q is QAB by default\n-IPN is IP by default\nRest arguments are mandatory to provide. \nFor example, perl copy_pkg_script_part2.pl -V 12.2.0 -id 132547 -N 2 -R 12.2 -I PBS-QAB2 -P 0 -t 1 -C copy-simple-1July2014.sh -incoming /homes/gridworks/pkg/jordan/internal/PBS_Professional/incoming/PBS-QAB2 -processed /homes/gridworks/pkg/jordan/internal/PBS_Professional/processed/PBS-QAB2 -prev /homes/gridworks/pkg/jordan/internal/PBS_Professional/processed/PBS-QAB1 -ip /homes/gridworks/pkg/jordan/IP2/PBS_Professional/software -nJ\n\n"; 


# Read options provided by user
my $result = GetOptions ("-nJ" => \$non_jenkin, "-V=s" => \$version, "-id=s" => \$buildid, "-N=s" => \$qabnum, "-R=s" => \$release, "-I=s" => \$internal, "-P=s" => \$ispatch, "-t=s" => \$trynum, "-h" => \$help, "-C=s" => \$copyscr, "-incoming=s" => \$incoming_path, "-processed=s" => \$processed_path, "-previous=s" => \$prev_rel, "-ip=s" => \$ip_path, "-Q=s" => \$qabname, "-IPN=s" => \$ipname, "-BT=s" => \$build_tag);

if ($help) {
  print $usage;
  exit 0;
}

if ($non_jenkin) {
  $non_jenkin=1;
}

if (!$version) {
  print "Please provide the PBS version.\n$usage\n";
  exit -1;
}
if (!$internal) {
  print "Please provide the Build directory for example, PBSPro_mainline.\n$usage\n";
  exit -1;
}
if (!$buildid) {
  print "Please provide build id from PBS build.\n$usage\n";
  exit -1;
}
if (!$qabnum) {
  print "Please provide QAB number.\n$usage\n";
  exit -1;
}
if (!$release) {
  print "Please provide release name or id; for example jordan or 12.2.\n$usage\n";
  exit -1;
}
if (!$incoming_path) {
  print "Please provide the incoming path.\n$usage\n";
  exit -1;
}
if (!$processed_path) {
  print "Please provide the processed path.\n$usage\n";
  exit -1;
}
if (!$prev_rel) {
  print "Please provide path to previous release.\n$usage\n";
  exit -1;
}
if (!$ip_path) {
  print "Please provide the IP path.\n$usage\n";
  exit -1;
}
if (!$non_jenkin) {
  if (!$build_tag) {
    print "Please provide build tag, -BT.\n$usage\n";
    exit -1;
  }
}

# change QAB and IP name to upper case
$qabname = uc($qabname);
$ipname = uc($ipname);
print "qab name is $qabname and IP name is $ipname\n";

# create the log file name and path.
# Log file will be created each time script is executed

my $home_path = "/homes/gridworks/pkg";
my $rel_path = $home_path . "/" . $release;
my $internal_path = $rel_path . "/internal/PBS_Professional/";

# create log directory

my $log_path = $internal_path . "log/";
if (!(-d $log_path)) {
  `mkdir -p -m 0775 $log_path`;
   print "Directory $log_path created\n";
} else {
   `chmod -Rf 775 $log_path`;
   print "Updated permissions for $log_path\n";
}


# create log file name
my $date = `date`;
$date =~ s/ /_/g;
my $logfile_name = "copy_pkg_script_log_" . $qabname . $qabnum . "_" . $date;

if ($ispatch) {
  # if it is a patch then insert patch name to log file name to differentiate
  $logfile_name = "copy_pkg_script_log_" . $qabname . $qabnum . "_" . $version . "_" . $
date;
}

# Construct the log file path
my $log = $log_path . $logfile_name;

# create the file
my $cmd = "touch $log";
print "executing $cmd\n";
my $rc = system($cmd);

if ($rc) {
  print "\nTrouble creating log file at $log. Exiting ...\n\n";
  exit -1;
}
else {
  print "\nLog file create at $log\n\n";
}

# change permissions for log file
$cmd = "chmod 766 $log";

print "executing $cmd\n";
$rc= system($cmd);
((print "Failed to change permissions for $log\n"), exit -1) if ($rc);

# Open the file for writing
open (MYLOG,">>$log") or die "cannot open log file $log $!";

print MYLOG localtime() . ": Script will run with following data\n";
print MYLOG "\nversion = $version \nBuildID = $buildid \nQABName = $qabname \nQABNum = $qabnum \nisPatch = $ispatch \nIPName = $ipname\nRelease = $release \nInternal_path = $internal\n-C = $copyscr\n-t = $trynum  \n\n";



# change to incoming path
print "\nchanging to $incoming_path\n";
print MYLOG localtime() . ": Changing to $incoming_path\n";

chdir ($incoming_path) or die "Cannot change directory to $incoming_path\n";

# rename old asc files
opendir (DIR,$incoming_path) or die "cannot open directory $incoming_path";

foreach my $f (readdir(DIR)) {
  if ($f =~ /.asc/) {
    my $newname = $f . ".bak";
    rename $f,$newname;
    print MYLOG "renamed $f as $newname \n";
  }
}

# Generate new checksum files

print MYLOG localtime() . ":  Generating new checksum files at" . `pwd` . "\n\n";
print "Generating new checksum files at" . `pwd` . "\n";

my @file = `ls $incoming_path | egrep 'tar.gz|.exe'`;

foreach my $i (@file) {
  my $tmp = $i;
  $tmp =~ s/tar.gz|exe/asc/ig;
  my $chkfile = $incoming_path . "/" . $tmp;
  open (FH,">$chkfile") or die "cannot create checksum file $chkfile\n$!\n";
  my $out = `/usr/bin/md5sum $i`;
  print FH $out;
  print MYLOG "Checksum created for $i\n";
}

# Diff the old and new checksum files

print MYLOG localtime() . ": Comparing the old and new checksum files under $incoming_path\n\n";
print "Comparing the old and new checksum files under $incoming_path\n\n";

my @file1 = `ls $incoming_path/*.asc`;

foreach my $j (@file1) {
  chomp($j);
  #print "New checksum file $j\n";
  my $bakfile = $j . ".bak";
  open (FILE,$j);
  open (FILE1,$bakfile);
  my $file = <FILE>;
  my $file_bak = <FILE1>;
  my @tmp = split (/\ +/,$file);
  my @tmp1 = split (/\ +/,$file_bak);

  # compare the contents of both checksum files.
  if ((chomp($tmp[0]) eq chomp($tmp1[0])) && (chomp($tmp[1]) eq chomp($tmp1[1]))) { 
    print MYLOG "\nno difference between $j and $bakfile\n";
   } else {
     print "$j and $bakfile are different. correct the error. Exiting ... \n\n";
     print MYLOG "$j and $bakfile are different. Exiting ... \n";
     exit -1;
  }
}

print "\nDone with the comparison of checksum files and all files look good\n";
print MYLOG localtime() . ": Done with the comparison of checksum files and all checksum files look good\n";

# verify if the process folder is correct. Then move to processed folder

print "Processed folder is $processed_path.";

if (!(-d $processed_path)){
  print "Creating $processed_path as it do not exist\n";
  $rc = `mkdir -p -m 0775 $processed_path`;
  if ($rc) {
    print "Error in creating $processed_path. Please create $processed_path manually and rerun the script with option -f2\n";
    exit -1;
  }
}

# Execute copy-simple script to rename the packages to processed folder for non-jenkins build. For jenkins use copy_incoming_to_processed.pl.

my $qab = $qabname . $qabnum;
my $ip = $ipname . $qabnum; 

if ($ispatch) {
 my $tmp = $internal;
 $tmp =~ s/PBS-//;
 $qab = $tmp;
}

my $copy_script;
my $cmd1;
if ($non_jenkin) {
  $cmd1 = "-I $release -B $buildid -r $version -Q $qab -P $ip";
  $copy_script = "/homes/gridworks/pbs/Packaging_scripts/" . $copyscr;
} else {
  #rename the packages created from jenkins build and create checksum
  $cmd1 = "-V $version -R $release -IPN $ipname -N $qabnum -Q $qabname -B $build_tag -P $ispatch";
  $copy_script = "perl /homes/gridworks/pbs/Packaging_scripts/copy_incoming_to_processed.pl";
}

print "\nStarting $copy_script $cmd1. It will take few minutes.\n\n";
print MYLOG localtime() . " : Starting $copy_script. It will take few minutes\n";

my $out = `$copy_script $cmd1`;
print MYLOG localtime() . ": Done with $copy_script. output = \n$out\n\n";
print "\nDone with $copy_script\n";
if ($?) {
  print "\nError in $copy_script. $out\n";
  exit -1;
}

# verify the packages created from previous releases
print "\nVerifying the packages against previous QABs\n";
print "previous path = $prev_rel\n";
@file = `ls $processed_path | egrep 'tar.gz|.exe' | sed 's/^PBSPro_.*-.*-.*-//'`;
@file1 = `ls $prev_rel | egrep 'tar.gz|.exe' | sed 's/^PBSPro_.*-.*-.*-//'`;

print MYLOG localtime() . ": Verifying the packages between $processed_path and $prev_rel\n\n"; 
my ($flag, @pkgmiss);

foreach my $j (@file) {
  #print "file is $j \n";
  $flag=0;
  foreach my $k (@file1) {
    if ($j =~ /$k/) {
      $flag=1;
      print MYLOG "Package $j exists\n";
      last;
    }
  }
  if ($flag == 0) {
    chomp($j);
    push (@pkgmiss,$j);
    print "package $j is missing\n";  
    print MYLOG "package $j is missing\n";
  }
}

my $len = @pkgmiss;
if ($len > 0) {
    print "\nWARNING!!!! $len package(s) are missing. They are \n @pkgmiss\n";
    print MYLOG localtime() . "WARNING!!! $len package(s) are missing. They are \n @pkgmiss\n";    
  } 
else {
  print "\nVerified that packages are present under $processed_path. \n\n";
  print MYLOG "\n" . localtime(). ": Verified that packages are present under $processed_path. \n\n";
}

print "Verifying if checksum are present for all the packages\n";
print MYLOG localtime() . ": Verifying if checksum are present for all the packages\n";

my @chksum = `ls $processed_path | egrep '.asc'`;
my $chksum_len = @chksum;
my $pkg_len = @file;

if (($chksum_len == $pkg_len) and ($chksum_len != 0)) {
  print "\nchecksum of all the packages are created. chksum_len=$chksum_len and pkg_len=$pkg_len\n\n";
  print MYLOG "Checksum of all the packages are present under $processed_path. Total number of packages are $pkg_len.\n\n";
} else {
  print "\nchecksum is missing for few packages. Only $chksum_len checksum files are present for $pkg_len packages. Please correct those manually.\n";
  print MYLOG "checksum is missing for few packages. Only $chksum_len checksum files are present for $pkg_len packages. Please correct those manually.\n";
  exit -1;
}

print "\nFiles are now ready to copy to IP location\n";
print MYLOG localtime() . "Files are now ready to copy to IP location\n\n";



my $i=0;
if (!(-d $ip_path)) {
  print "Creating $ip_path as it do not exist.\n";
  $rc = `mkdir -p -m 0775 $ip_path`;
  if ($rc) {
     print "Error in creating $ip_path. Please create it manually and rerun the script with option -f2\n";
     exit -1;
  }
}
 
print "\nCopying the files from $processed_path to $ip_path\n\n";
print MYLOG localtime() . ": Copying the files from $processed_path to $ip_path\n\n";

$cmd = "cp $processed_path/* $ip_path";
 #copy_file($processed_path, $ip_path) or die "Error in copying files from $processed_path to $ip_path"; #system($cmd);
$rc = `cp $processed_path/* $ip_path`;
if ($rc) {
  print "Error in copying files from $processed_path to $ip_path\n";
  exit -1;
}

print "\nCopied the files successfully to $ip_path\n";
print MYLOG localtime() . ": Copied the files successfully to $ip_path\n\n";

# verify the checksum file once again at ip location
print MYLOG "\nChanging to $ip_path\n";
chdir($ip_path) or die "Failed to change to $ip_path\n";
print "\nRunning /homes/gridworks/buildtools/Checksum_Check.sh to verify the checksum files\n";
print MYLOG localtime() . ": Running /homes/gridworks/buildtools/Checksum_Check.sh to verify the checksum files\n";

$cmd = "sh /homes/gridworks/pbs/Packaging_scripts/Checksum_Check1.sh";
$rc = system($cmd);

if ($rc) {
  print "\nproblem with checksum files\n\n";
  print MYLOG localtime() . ": Problem with checksum files\n\n";
  exit -1;
}
print "\nchecksum files are verified and they look good.\n\n";

# update the permissions of the files at IP path
my @files = `ls | egrep '.tar.gz|.asc'`;
foreach my $f (@files) {
  `chmod -f 664 $f`;
}
print "\n File permissions updated to 664 at $ip_path\n";
print MYLOG localtime() . ": File permissions updated to 664 at $ip_path\n";

print "\nLog a JIRA ticket to copy the files to release area\n";
print MYLOG localtime() . ": Checksum files are verified and they look good.\nLog a JIRA ticket to copy the files to release area.\n";

exit 0;
