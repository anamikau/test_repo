#! /usr/pkg/bin/perl -w

use Getopt::Long;
use strict;
use Time::Local;
use File::Compare;
#use List::Moreutils qw(uniq);


$SIG{INT} = 'INT_handler'; 

#===================================================

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

######################
# Summary: read BUILD_LIST and returns the list of machines that are built
# Input: build path
# Return: list of machines that were build
sub get_build_list($) {
  my $build_path = shift;
  my $build_file = $build_path . "/BUILD_LIST";
  open(FILE,$build_file) or print "fail to open $build_file\n",return 0;
  my @lines = <FILE>;
  my @build_machine;
  foreach my $i (@lines) {
      my @tmp = split (/\ /,$i);
      push (@build_machine,$tmp[0]);
  } 

  return @build_machine if (@build_machine);
  return 0;
} 

##########################
# Summary: Verify if binaries are built for each machine
# Input: build path
# Return: list of missing packages if any else null

sub  verify_packages($) {
   my $build_path = shift;
   my @machines = get_build_list ($build_path);
   my @missing_pkg;
   print "\n\nVerify if all the platforms listed in BUILD_LIST are built succesfully\n\n";
   foreach my $i (@machines) {
     my $pkg_dir = join ('/',$build_path,$i,"installers");
     if (-e $pkg_dir) {
       #print "\n$pkg_dir exists\n";
       opendir (DIR,$pkg_dir);
       my @files = readdir(DIR);
       foreach my $file (@files) {
	 if ($file =~ /tar.gz|.exe/i) {
	   print "Found package $file for $i\n";
	 } elsif (!($file =~ /^\./))  {
	   push (@missing_pkg,$i);
	   print "no package for platform $i\n";
         }
       }
     } else {
       push (@missing_pkg, $i);   
       print "no package for platform $i\n";
     }
   }
   
   return @missing_pkg;

}


#######################
# Summary: get the version number in decimal format
# Input: version
# return: version number in decimal form 
sub get_version_number($) {
  my $version = shift;
  my ($major,$minor,$patch) = split (/\./,$version);
  my $ver = ((($major*1000+$minor)*1000)+$patch);
  return $ver;
}

#######################
# Summary: create checksum files on cvs for each binary file
# Input: location of build  , build parent directory, build directory
# Return: list of files that failed to create checksum else null 
sub create_checksum ($$$) {
  my $build_loc = shift;
  my $builddir = shift;
  my $build_path = shift;
  my @machines = get_build_list($build_loc);
  my $chksum_dir = "/r/shared/groups/releng/md5_data/";
  my $tgtdir = join ("/",$chksum_dir,$builddir,$build_path);
  my @chksum_err;

  # Create target directory if not already exists
  if (!(-e $tgtdir)) {
    my $cmd = "mkdir -p -m 0775 $tgtdir";
    my $rc = system($cmd);
    if ($rc) {
      print "\nError in $cmd. Please remove errors and rerun the script.\n";  
      return 0;
    }
    print "$tgtdir created\n";
  } 

  foreach my $i (@machines) {
    my $srcdir = join ("/",$build_loc,$i,"installers");
    if (-e $srcdir) {
      # change directory to srcdir
      chdir($srcdir);
      my $chksum_dir = join ("/",$tgtdir,$i);
      opendir (DIR,$srcdir);
      my @files = readdir(DIR);
      foreach my $f (@files) {
	if ($f =~ /tar.gz|exe/) {
	  #create chksum directory under tgtdir
	  if (!(-e $chksum_dir)) {
	    `mkdir -p -m 0775 $chksum_dir`;
          }
	  my $chksum_file = $f;
	  $chksum_file =~ s/tar.gz|exe/asc/i;
	  my $chksum_path = join ("/",$chksum_dir,$chksum_file);

	  #calculate chksum
	  my $cmd = "/usr/bin/md5 -n $f > $chksum_path";
	  my $rc = system($cmd);
	  if ($rc) {
	    push (@chksum_err,$chksum_file);
          }
        }
      }
      closedir(DIR);
    }
  }
  return @chksum_err;
}

#===================================================

my $version = ''; #PBS build version
my $builddir = ''; #PBS build directory name on cvs under ~pbsbuild 
my $buildid = ''; # PBS build id
my $qabnum = ''; # QAB id
my $trynum = 1; # try number
my $debug = 0; # if DEBUG
my $ispatch = 0; # if is a patch
my $release = ''; # PBS release. for example, 12.2 or jordan
my $help = 0; # help to print usage
my $internal = ''; # QAB location inside internal. for example, PBS-QAB1
#my $copyscr = "copy.simple-1July2014.sh"; # name of the copy.simple script
my $copyscr = "copy.simple-27Oct2014.sh"; # name of the copy.simple script
my $user = '';
my $flag = 0;
my $qabname = "QAB";
my $ipname = "IP";
my $non_jenkin = 0; # flag to make jenkin installation as default

my $usage = "Usage for copy_pkg_script.pl --- \n\nRun following as pbsbuild\nsudo -u pbsbuild perl copy_pkg_script.pl -V <PBS build version> -R <PBS release id> -i <PBS build id> -B <Build directory on cvs> -Q <QAB name> -N <QAB number> -T <try number. Default is 1> -u <login name for bldlnx04> -D <0|1 for debuging> -P <0|1 for patches> -C <copy script name on bldlnx04> -L <directory inside incoming path> -IP <IP Name> -f2 <if set then runs only the second half of the copy script on bldlnx04> -nJ <if set run the copy for non_jenkin builds> \n\nWhere,\n-P is 0 by default\n-T is 1 by default\n-C is copy.simple-27Oct2014.sh by default\n-Q is QAB by default\n-IP IP by default.\nif -f2 is not specified script will run completely. Else it will skip the first half on CVS and directly jumps to bldlnx04.\nRest arguments are mandatory to pass\nFor example,\nperl copy_pkg_script.pl -V 12.2.0 -B PBSPro_mainline -R 12.2 -i 132547 -Q PQAB -N 2 -T 1 -IP PIP -P 0 -D 1 -L PBS-PQAB2 -u anamika -nJ\n";

# Read options provided by user
my $result = GetOptions ("-nJ" => \$non_jenkin, "-V=s" => \$version, "-B=s" => \$builddir, "-i=s" => \$buildid, "-N=s" => \$qabnum, "-T=s" => \$trynum, "-D=s" => \$debug, "-P=s" => \$ispatch, "-R=s" => \$release, "-h" => \$help, "-C=s" => \$copyscr, "-L=s" => \$internal, "-f2" => \$flag, "-u=s" => \$user, "-Q=s" => \$qabname, "-IP=s" => \$ipname);

if ($help) {
  print $usage;
  exit 0;
}

if ($non_jenkin) {
  $non_jenkin=1;
  print "Running copy script for non_jenkin builds\n";
}

if (!$version) {
  print "Missing option -V, please provide PBS version\n$usage\n";
  exit -1;
}
if (!$builddir) {
  print "Missing option -B, please provide Build directory. For example, PBSPro_mainline\n$usage\n";
  exit -1;
}
if (!$buildid) {
  print "Missing option -i, please provide build id from PBS build\n$usage\n";
  exit -1;
}
if ($qabnum eq "NULL" && $qabnum != '0') {
  print "Missing option -N, please provide QAB number\n$usage\n";
  exit -1;
}
if (!$release) {
  print "Missing option -R, please provide release name or id; for example jordan or 12.2\n$usage\n";
  exit -1;
}
if (!$internal) {
  print "Missing option -L, please provide QAB name under internal directory on bldlnx04. For example, PBS-QAB1\n$usage\n";
  exit -1;
}
if (!$user) {
  print "Missing option -u, please provide the login name for bldlnx04.\n$usage\n";
  exit -1;
}

# change qab and IP name to upper case
$qabname = uc($qabname);
$ipname = uc($ipname);
print "QA build is $qabname and IP is $ipname\n";

#create log file name and path. This will be created each time the script is run with the current timestamp.

my $rel_path = "/release-archive/WebReleaseArchive/" . $release; # release path

# create log directory inside release dir
my $logdir = $rel_path . "/log/";
if (!(-d $logdir)) {
  `mkdir -p -m 0775 $logdir`;
  print "Directory $logdir created\n";
} else {
   `chmod -Rf 775 $logdir`;
   print "updated permissions for $logdir\n";
}

# create log file name
my $date = `date`;
$date =~ s/ /_/g;
my $logfile_name = "copy_pkg_script_log_" . $qabname . $qabnum . "_" . $date;

if ($ispatch) {
  # if it is a patch then insert patch name to log file name to differentiate
  $logfile_name = "copy_pkg_script_log_" . $qabname . $qabnum . "_" . $version . "_" . $date;
}

# Construct the log file path 
my $log_path = $logdir . $logfile_name;


# Open the file for writing
open (MYLOG,">>$log_path") or die "cannot open log file $log_path $!";
print "\nCreated log file $log_path\n";

# change the file permissions
my $cmd = "chmod 766 $log_path";
system($cmd);

print MYLOG localtime() . ": Script will run with following data\n";
print MYLOG " version = $version \n BuildDir = $builddir \n BuildID = $buildid \n QABNum = $qabnum \n QABName = $qabname\n IPName = $ipname\n trynum = $trynum \n isPatch = $ispatch \n Release = $release \n Internal = $internal \n Copy script = $copyscr \n User = $user\n\n"; 

# Set path for release directory
my $pkg_path = "/" . $qabname . $qabnum . "/try" . $trynum;

if ($ispatch) {
  #insert patch version in the path name
  $pkg_path =  "/" . $version . $pkg_path;
}

$rel_path = $rel_path . $pkg_path;
#print "$rel_path ....\n\n";

if ($non_jenkin) {
  my $i=0;
  while (!(-d $rel_path)) {
    print "$rel_path do not exist. Create using \" sudo -u pbsbuild mkdir -p -m 0775\". Waiting $i\n";
    $i+=1;
    sleep 5;
  }
  $i=0;
  while (!(check_perm($rel_path))) {
    print "Permissions for $rel_path are not matching to 0775. Kindly update those. Waiting $i\n";
    $i+=1;
    sleep 5;
  }
}

#my $ver = get_version_number($version);
#print "version is $ver\n";

my $release_dir="/release-build/pbsbuild/";
my $build_path = "PBSPro_" . $version . "." . $buildid;
my $build_tag;

# For jenkins build, build path will be suffixed with build tag
if (!$non_jenkin) {
  my $build_tmp = join ("/", $release_dir,$builddir);
  opendir (DIR,$build_tmp);
  my @files = readdir(DIR);
  foreach my $file (@files) {
    if ($file =~ /$build_path/ig) {
      $build_tag = $file;
      my $tmp = $build_path . '-';
      $build_tag =~ s/$tmp//;
      #$build_tag =~ /^\-(\w+)/i;
      #$build_tag = $1;
      $build_path = $file;
      print "Build Tag is $build_tag\nAnd new build path for jenkins build is $build_path";
    }
  }
}

my $build_loc = join ("/",$release_dir,$builddir,$build_path);
my @build_machine = get_build_list($build_loc) ;
#print "\nlist of platforms that has been built\n@build_machine\n";
my @missing_pkg;


if (!$flag) {

  # Making old installation as not default and jenkins build copy as default.
  if ($non_jenkin) {

   print MYLOG localtime() . ": Running create_builddir_checksum.sh -W $version -V $version -B $builddir -i $buildid \n\n";
   print "\nRunning create_builddir_checksum.sh -W $version -V $version -B $builddir -i $buildid \n";
   print "press Y to continue or N for exiting:";
   my $ans = <>;

   if ($ans =~ /N/i) {
     print "\nexiting from copy script\n";
     print MYLOG "\nexiting from copy script\n";
     exit -1;
   }
   if (!($ans =~ /Y/i)) {
     print "\nInvalid character $ans passed to the screen. Exiting ...\n";
     print MYLOG `date` . ": Invalid character $ans passed to the screen. Exiting ...\n";
     exit -1;
   }

   print "\nStarting create_builddir_checksum.sh. It will take sometime.\n\n";

   my $out_build;

   $out_build = `/r/shared/groups/releng/bin/create_builddir_checksum.sh -W $version -V $version -B $builddir -i $buildid 2>&1`;
   print MYLOG "\n" . localtime() . ": executed create_builddir_checksum.sh with output ---- \n $out_build \n";
   print "\nDone with the execution of create_builddir_checksum.sh\n";

   my $tmp_path = $release . $pkg_path; # temporary path to be passed as an argument to rc_dnload
   print MYLOG localtime() . ": executing rc_dnload.sh -W $version -V $version -i $buildid -P $builddir -t $tmp_path\n\n";
   print "\nexecuting rc_dnload.sh -W $version -V $version -i $buildid -P $builddir -t $tmp_path\n";
   print "Press Y to continue or N to exit:";
   $ans = <>;

   if ($ans =~ /N/i) {
      print "\nexiting from copy script\n";
      exit -1;
   }
   if (!($ans =~ /Y/i)) {
     print "\nInvalid character $ans passed to the screen. Exiting ...\n";
     exit -1;
   }

   # execute rc_dnload.sh to copy and rename the packages.
   print "\nStarting rc_dnload.sh. It will take sometime\n\n";
   print MYLOG localtime() .": Starting rc_dnload.sh. It will take sometime\n";
   $out_build = `/r/shared/groups/releng/bin/rc_dnload.sh -W $version -V $version -i $buildid -p $builddir -t $tmp_path 2>&1`;

   print MYLOG localtime() . ": Done with the execution of rc_dnload.sh. $out_build \n\n";
   print "\n Done with the execution of rc_dnload.sh. exit status=$?\n\n";
   if ($?) {
     print "rc_dnload.sh failed to copy the packages to $tmp_path; $! \n";
     exit -1;
   }

   # Verify the packages copied with previous QABs or releases
   print "\n Verify the packages copied with previous QABs or releases\n";
   my ($qabprev, $relprev, $cmppath);

   print "\nEnter the complete path to compare the package against. For example,\n/release-archive/WebReleaseArchive/12.1/12.1.1/QAB1/try1\n";
   $cmppath = <>;
   chomp($cmppath);
   print "\nyou entered $cmppath\n";
   print MYLOG "\ncompare path is $cmppath\n";

   if (!(-d $cmppath)) {
      print "path you entered is $cmppath which do not exist.Please enter a valid path and try again.\n";
      print MYLOG localtime() . ": Path $cmppath do not exist. Exiting ... \n";
      exit -1;
   }

   print "\ncompare the packages with previous QABs \($cmppath\) to see if all packages are present\n";


   # list the package names and store in a temporary file
   my @out1 = `ls $cmppath | egrep '.tar.gz|.exe' | sed 's/^PBSPro_.*-//'`;
   my @out2 = `ls $rel_path | egrep '.tar.gz|.exe' | sed 's/^PBSPro_.*-//'`;
   #print "out1=@out1\nout2=@out2\n";

   my (@pkgmiss, $flag1, $pkg_len);

   $pkg_len = @out2; # @pkglist1; #get the count of packages
   foreach my $i (@out2) {
     $flag1=0;
     chomp($i);
     foreach my $j (@out1) {
       chomp($j);
       if ($i =~ /$j/ig) {
          $flag1=1;
          print MYLOG "package $i exists\n";
          last;
       }
     }
     if ($flag1 == 0) {
       push (@pkgmiss,$i); 
       print "package $i is missing\n";
     }
    }
  
   my $len = @pkgmiss;
   #print "len = $len\n";
   if ($len > 0) {
     print "$len packages are missing. Do you want to continue? Y/N\n";
     $ans = <>;
     if ($ans =~ /N/i) {
       print "exiting ...\n";
       exit -1;
     }
     if (!($ans =~ /Y/i)) {
       print "Invalid character passed. Taking default as yes\n";
      }
   }
   print "\nverified the packages between both the builds/releases. They look good.\n\n";
   print MYLOG localtime() . ":Verified the package between both the builds/releases. They look good.\n";
   print "Create checksum of the packages\n\n";

   my $cmd_list = "-I $release -Q $qabnum -T $trynum -D $debug -QAB $qabname";

   if ($ispatch) {
     my $patchver = $version . "/" . $qabname . $qabnum . "/try" . $trynum;
     $cmd_list =  " -I $release -D $debug  -P $patchver -QAB $qabname";
   }
   print MYLOG localtime() . ": running /r/shared/groups/releng/bin/create_RCdir_checksum.sh $cmd_list\n\n";
   print "\n Starting create_RCdir_checksum.sh $cmd_list. This will take few minutes. \n\n";
   my $out1 = `/r/shared/groups/releng/bin/create_RCdir_checksum.sh $cmd_list 2>&1`;

   print MYLOG localtime() . ": output of create_RCdir_checksum.sh:\n $out1 \n\n";
   print "\nDone with create_RCdir_checksum.sh. Exit status = $?\n\n"; 

   print MYLOG ": verify if checksum of all the files have been created\n\n";

   my @chksum_len = `ls $rel_path | egrep '.asc'`;

   my $chksum_len = @chksum_len;
   if (($chksum_len == $pkg_len) and ($chksum_len != 0)) {
     print "checksum of all the packages are created. $pkg_len == $chksum_len\n";
     print MYLOG localtime() . ": checksum of all the packages are created. $pkg_len == $chksum_len\n";
   } else {
     print "\nchecksum is missing for few packages. please correct before copy. Exiting ...\n\n";
     exit -1;
   }

   # update the permissions for .gz and .asc files for $rel_path
   chdir ($rel_path) or die "cannot change to directory $rel_path: $!";
   my @files = `ls | egrep '.tar.gz|.asc'`;
   foreach my $f (@files) {
     #chmod(664,$f);
     `chmod 664 $f`;
   }
   print MYLOG localtime() . ": Permissions for file at $rel_path are changed to 664\n\n";

   # change the group ownership to pbssrc
   `chgrp pbssrc *`;

   print MYLOG localtime(). ": Group ownership of files at $rel_path changed to pbssrc\n";
    
 } # end of non_jenkin 
 else { # For packages produced by jenkins build
    # Verify if build is done for all the platforms.
    @missing_pkg = verify_packages($build_loc);
    if (@missing_pkg) {
      print "Package for following platform(s) are missing.\n\n@missing_pkg\n\nDo you want to continue ([y]/n):";
      my $ans = <>;
      if ($ans =~ /N/i) {
        print "Exiting ...\n";
	print MYLOG localtime() . ":Package for following platform(s) are missing hence exiting.\n @missing_pkg\n.";
        exit -1;
      }
    }

    # create checksum files
    print "Creating checksum files\n";
    print MYLOG localtime(). ":Creating checksum files\n"; 
    my @chksum_err = create_checksum($build_loc,$builddir,$build_path);
    if (@chksum_err) {
      print "Following chksum files are missing\n@chksum_err\nDo you wish to continue ([Y]/N):\n";
      my $ans = <>;
      if ($ans =~ /N/i) {
	print "Exiting ...\n";
	print MYLOG localtime() . ":Following chksum files are missing hence exiting.\n@chksum_err\n";
	exit -1;
      }
    }
    print "Checksum files are created\n";
    print MYLOG localtime(). ":Checksum files are created\n";
 } #end of jenkin check 

} # end of flag


# copy of files to bldlnx04

# construct the incoming path on bldlnx04

my $home_path = "/homes/gridworks/pkg";
my $rel_path1 = $home_path . "/" . $release;
my $internal_path = $rel_path1 . "/internal/PBS_Professional/";
my $incoming_path = $internal_path . "incoming/" . $internal;
my $processed_path = $internal_path . "processed/" . $internal;


# Validate the incoming path to copy the packages

print "\nincoming path on bldlnx04 where packages needs to be copied is \n $incoming_path.\nIs this correct? Y/N:";
my $ans = <>;

if ($ans =~ /N/ig) {
  print "\nProvide the correct path:";
  $incoming_path = <>;
  chomp($incoming_path);
  print "\nincoming path is now updated to $incoming_path\n";
  print MYLOG localtime() . ": incoming path is now updated to $incoming_path\n";
}
elsif (!($ans =~ /Y/i)) {
  print "\nInvalid character $ans. Taking default as yes\n";
}

print "\nProcessed path on bldlnx04 where packages needs to be copied after renaming and checksum will be generated is \n$processed_path. Is this correct? Y/N:";
$ans = <>;

if ($ans =~ /N/ig) {
  print "Provide the correct path:";
  $processed_path = <>;
  chomp($processed_path);
  print "\nProcessed path is now updated to $processed_path\n";
  print MYLOG localtime() . ": Processed path is now updated to $processed_path\n";
}
elsif (!($ans =~ /Y/i)) {
  print "\nInvalid character $ans. Taking default as yes\n";
}

print "\nEnter the complete path of QAB for comparing the packages against on bldlnx04. \nFor Example,\n /homes/gridworks/pkg/jordan/IP1/PBS_Professional/software\n";
my $prev_rel = <>;
chomp($prev_rel);
print MYLOG localtime() . ": Previous release path is now set to $prev_rel\n\n";
print "\nPrevious release path is now set to $prev_rel\n";

my $ip = $ipname;

my $ip_loc = "/" . $ip . $qabnum;
if ($ispatch) {
  $ip_loc = "/" . $version . "_" . $ip . $qabnum;
}
my $ip_path = $rel_path1 . $ip_loc . "/PBS_Professional/software/";

print "\nIP path is $ip_path. Is this correct? [Y]/N:";
$ans = <>;

if ($ans =~ /N/i) {
  print "Enter a different path:";
  $ip_path = <>;
  chomp($ip_path);
  print "\nIP path has been updated to $ip_path\n";
  print MYLOG localtime() . ": IP path has been updated to $ip_path\n\n";
}
elsif (!($ans =~ /Y/i)) {
  print "\nInvalid character $ans. Taking Y as default\n";
}

print "\nStarting with the copy from cvs:$rel_path to bldlnx04:$incoming_path\nFor continuing type 'C' else it will skip:";
$ans=<>;
chomp($log_path);
if ($ans =~ /C/i) {

  # Create incoming directory if not already exists
  print "Create $incoming_path at bldlnx04 if not already exists\n";
  my $cmd = "ssh $user\@bldlnx04 mkdir -p -m 0775 $incoming_path";
  system($cmd);

  if (!$non_jenkin) { # For jenkins build it can be directly copied from /release-build location on cvs
    
    my $pkg_dir = "installers"; #earlier it was wraps


    print "\nStarting copying the packages from idocs:$build_loc to bldlnx04:$incoming_path.\n** To avoid entering the password please create passwordless session for your user login between idocs and bldlnx04. Follow the instructions from README.\n\n";
    print MYLOG localtime() . "\n\nStarting copying the packages from idocs:$build_loc to bldlnx04:$incoming_path.\n";

    foreach my $i (@build_machine) {
      if (grep (/$i/, @missing_pkg)) {
	print "Skipping copy of $i as package is missing\n";
	#next;
      } else {
        my $pkg_tmp = join ('/',$build_loc,$i,$pkg_dir);
	my $chksum = "/r/shared/groups/releng/md5_data/" . $builddir . "/" . $build_path . "/" . $i; 
        if (-e $pkg_tmp) {
	  opendir (DIR1,$pkg_tmp);
	  my @pkgs = readdir(DIR1);
          closedir(DIR1);

	  foreach my $f (@pkgs) {
	    if ($f =~ /tar.gz|exe/i) {
	      my $pkg = join ("/",$pkg_tmp,$f);
	      my $pkg_incoming = join ("/",$incoming_path,$f);

              # copy the package if not exist
	      my $cmd = "/usr/pkg/bin/rsync $pkg $user\@bldlnx04:$incoming_path";
	      print "\nCopying $pkg \@bldlnx04:$incoming_path. Please enter password when/if prompted.\n";
	      my $rc = system($cmd);
	      if ($rc) {
	        print "\n Error in command $cmd\n";
	        print MYLOG localtime() . "\nError in command $cmd\n";
	        exit -1;
              }
              print MYLOG localtime() . "command $cmd is successful\n";
              
	      # check if checksum file exists
	      my $chk_tmp = $f;
	      $chk_tmp =~ s/tar.gz|exe/asc/;
	      my $chk_incoming = join ("/",$incoming_path,$chk_tmp);
	      my $chk = join ("/",$chksum,$chk_tmp);

	      my $cmd1 = "/usr/pkg/bin/rsync $chk $user\@bldlnx04:$incoming_path";
              print "\nCopying $chk \@bldlnx04:$incoming_path. Please enter password when/if prompted.\n";
	      my $rc1 = system($cmd1);
	      if ($rc1) {
	         print "\nError in command $cmd1. Please rectify the error and rerun the script\n";
	         print MYLOG localtime() . "Error in command $cmd1. Please rectify the error and rerun the script\n";
	         exit -1;
	      }
	      print MYLOG localtime() . "$cmd1 is successfull\n";
	     }
           }
         }
       }
    }
  } # end of jenkins build copy to TROY
  else { # For non-jenkin build use previous approach
     $cmd = "/usr/pkg/bin/rsync $rel_path\/\* $user\@bldlnx04:$incoming_path";

     print "Starting with the copy of files to bldlnx04 in background. \nCMD = $cmd\nIt will take approx 1-2h\n";
     print MYLOG localtime() . ": Starting with the copy of files to bldlnx04 in background. \nCMD = $cmd\nIt will take approx 1-2h\n\n";
     print "\nPlease enter your password at the prompt below:\n";
     my $rc = system($cmd);
     if ($rc) {
       print "\nError in copying packages from $rel_path to $incoming_path\n";
       exit -1;
     }
   } # end of copy for non-jenkin build
   print "\nAll the packages has copied successfully under $incoming_path\n";
   print "\n" . localtime() . ": All the packages has copied successfully under bldlnx04:$incoming_path\n\n";
	 
 # } #end of copy for non-jenkin build
} # end of copy

# check if all the files are copied to incoming path
if ($non_jenkin) {
  print "\nVerifying if all the packages has been copied on bldlnx04\n";
  print MYLOG localtime() . ": Verifying if all the packages has been copied on bldlnx04\n\n";

  my @files = `ls $rel_path| grep PBSPro_`;
  my $len1 = @files;

  print "Please enter your password at the prompt below:\n";
  $cmd = "ls $incoming_path | grep PBSPro_";
  my @len_out = `ssh -l $user bldlnx04 $cmd`;

  my $len2 = @len_out;
  print "len1=$len1 and len2=$len2\n";

  if ($len1 != $len2) {
    print "\nnot all files are copied. Wait till files are copied and rerun this script with option -f2.\n";
    exit -1;
  }

  print "Files have been copied successfully to $incoming_path at bldlnx04\n";
  print MYLOG localtime() . ": Files have been copied successfully to $incoming_path at bldlnx04\n\n";
} #end of verification for non-jenkin build

print "\n Starting the copy script part 2 on bldlnx04. Please enter your password when prompted:\n";
print MYLOG localtime() . ": Starting the copy script part 2 on bldlnx04\n\n";

if ($non_jenkin) {
	$cmd="ssh -l $user bldlnx04 perl /homes/gridworks/pbs/Packaging_scripts/copy_pkg_script_part2.pl -V $version -id $buildid -R $release -Q $qabname -N $qabnum -t $trynum -P $ispatch -I $internal -IPN $ipname -C $copyscr -incoming $incoming_path -processed $processed_path -previous $prev_rel -ip $ip_path -nJ"; ## missing -BT
} else {
	$cmd="ssh -l $user bldlnx04 perl /homes/gridworks/pbs/Packaging_scripts/copy_pkg_script_part2.pl -V $version -id $buildid -R $release -Q $qabname -N $qabnum -t $trynum -P $ispatch -I $internal -IPN $ipname -C $copyscr -incoming $incoming_path -processed $processed_path -previous $prev_rel -ip $ip_path -BT $build_tag";
}
system($cmd);

if ($?) {
  print "\nError in executing copy_pkg_script_part2.pl on bldlnx04\n";
  exit -1;
}

print "\nCopy script is done successfully.\n\n";

print MYLOG localtime() . ": Copy script is done successfully.\n\n";


exit 0;
