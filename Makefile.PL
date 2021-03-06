# -*- cperl -*-

use 5.005;
use Config;
BEGIN {

    if ($] == 5.008 && $ENV{"LANG"} ne "C" && $^O ne 'MSWin32') {
	$ENV{LANG} = "C";
	print STDERR "\n\n\n\$ENV{LANG} is not 'C' execing 'perl Makefile.PL'".
	" with ENV{LANG} == 'C'\n You can skip this check by: 'export ".
	"LANG='C' before running 'perl Makefile.PL or by upgrading your Perl'\n\n\n";

	sleep(5);
        exec ($Config{perlpath}, $0, @ARGV )|| die $!;
    }
}
use strict;
BEGIN { $^W = 1; }
use Getopt::Long();
use ExtUtils::MakeMaker();
use Data::Dumper ();
use File::Path;
use File::Copy;
use File::Basename;
require DBI::DBD;

my $TESTDB = "test";

use vars qw($opt);
$opt = { "help" => \&Usage, };

Getopt::Long::GetOptions(
    $opt,
    "help",
    "testdb=s",
    "testhost=s",
    "testport=s",
    "testuser=s",
    "testpassword=s",
    "testsocket=s",
    "cflags=s",
    "libs=s",
    "verbose",
    "ps-protocol",
    "bind-type-guessing",
    "nocatchstderr",
    "ssl!",
    "nofoundrows!",
    "embedded=s",
    "mysql_config=s",
    "force-embedded",
	"with-mysql=s"
    ) || die Usage();

my $source = {};

  #Check for mysql_config first
  $source->{'mysql_config'}="guessed";
  if ($opt->{'mysql_config'})
  {
	$opt->{'mysql_config'} = Win32::GetShortPathName($opt->{'mysql_config'})
        if $^O eq 'MSWin32';
    if (-f $opt->{'mysql_config'})
    {
      $source->{'mysql_config'} = "Users choice";
    }
    else
    {
      print <<"MSG";

Specified mysql configuration script '$opt->{'mysql_config'}' doesn't exist. 
Please check path/permissions. Will try to use default mysql_config 
script found through PATH.
MSG
      $opt->{'mysql_config'}= "mysql_config";
    }
  }
  else
  {
	if ($^O eq 'MSWin32')  {
		win32_mysql_config($opt->{'with-mysql'});
	}
    if (! `mysql_config`)
    {
      print <<MSG;

Cannot find the file 'mysql_config'! Your execution PATH doesn't seem 
not contain the path to mysql_config. Resorting to guessed values!
MSG
    }
    $opt->{'mysql_config'} = "mysql_config";
  }

for my $key (qw/testdb testhost testuser testpassword testsocket 
                    cflags embedded libs nocatchstderr ssl nofoundrows
                    ps-protocol bind-type-guessing force-embedded/)
{
  Configure($opt, $source, $key);
}

#We have to rename/move Makefile.PL in mysqlEmb directory
#since MakeMaker will find it and will try to execute it.
if (-f "mysqlEmb/Makefile.PL")
{
  eval { require File::Copy };
  move ("mysqlEmb/Makefile.PL", "mysqlEmb/Makefile.PL.old");
}

#Disable of building of dbd::mysqlEmb driver by default
$opt->{'embedded'}="" if !$opt->{'force-embedded'};

if ($opt->{'embedded'})
{
  if ($source->{'embedded'} eq 'mysql_config')
  {
    #We have to use libmygcc to resolve linking problem  
    # this causes problems for cygwin
    #$opt->{'embedded'} .= " -lmygcc";
    # Under Cygwin (at least) we have to use libstdc++ to resolve linking
    # problem because libmysqld is built using g++ rather than gcc.
    $opt->{'embedded'} .= " -lstdc++";
  }

  my @files = ($^O =~ /mswin32/i) ? qw(mysqlclient.lib) :
               qw(libmysqld.a);

  my @dirs = $opt->{'embedded'} =~ /-L(.*?)(?:\s|$)/g;

  if( !(SearchFor('lib', @files)) && !(SearchFor2(\@files,\@dirs)) )
  {
     warn <<"MSG";

You intended to build DBD::mysqlEmb driver by using option:
--embedded=$opt->{'embedded'}.
But we failed to determine directory of @files. Building of DBD::mysqlEmb
driver was disabled.

Please use

  perl Makefile.PL --embedded="-L<dir> <flags>"

to set correct directory. For details see the INSTALL.html file,
section "Linker flags" or type

  perl Makefile.PL --help
MSG
     $source->{'embedded'} = "guessed";
     $opt->{'embedded'}="";
  }
}

if ($opt->{'embedded'} && !check_include_version($opt->{'cflags'}, 40003)) {
  die <<"MSG";

WARNING: Wrong version or unable to check version of mysql include files.
To build embedded  version of DBD you ought to be sure that you use include
files from MySQL server >= 4.0.3.

MSG
}

print <<"MSG";
I will use the following settings for compiling and testing:

MSG

delete $opt->{'help'};
my $keylen = 0;
for my $key (keys %$opt)
{
  $keylen = length($key) if length($key) > $keylen;
}
my $slen = 0;
for my $val (values %$source)
{
  $slen = length($val) if length($val) > $slen;
}

for my $key (sort { $a cmp $b} keys %$opt)
{
  printf("  %-" . $keylen . "s (%-" . $slen . "s) = %s\n",
	 $key, $source->{$key}, $opt->{$key})
}

print <<"MSG";

To change these settings, see 'perl Makefile.PL --help' and
'perldoc INSTALL'.

MSG

sleep 5;

eval { require File::Spec };
my $dsn= '';
if (exists $opt->{'ps-protocol'}) {
  $dsn = "\$::test_dsn .= \";mysql_server_prepare=1\";\n"; 
}
elsif (exists $opt->{'bind-type-guessing'}) {
    $dsn= "\$::test_dsn .= \";mysql_bind_type_guessing=1\";\n"; 
}
my $fileName = $@ ?
  "t/mysql.mtest" : File::Spec->catfile("t", "mysql.mtest");
(open(FILE, ">$fileName") &&
 (print FILE ("{ local " . Data::Dumper->Dump([$opt], ["opt"]) .
	      "\$::test_host = \$opt->{'testhost'};\n" .
	      "\$::test_port = \$opt->{'testport'};\n" .
	      "\$::test_user = \$opt->{'testuser'};\n" .
              "\$::test_socket = \$opt->{'testsocket'};\n" .
	      "\$::test_password = \$opt->{'testpassword'};\n" .
	      "\$::test_db = \$opt->{'testdb'};\n" .
	      "\$::test_dsn = \"DBI:mysql:\$::test_db\";\n" .
	      "\$::test_dsn .= \";mysql_socket=\$::test_socket\" if \$::test_socket;\n" .
              "\$::test_dsn .= \":\$::test_host\" if \$::test_host;\n" .
	      "\$::test_dsn .= \":\$::test_port\" if \$::test_port;\n".
              $dsn .
	      "} 1;\n"))  &&
  close(FILE))  ||  die "Failed to create $fileName: $!";


my $cflags = "-I\$(DBI_INSTARCH_DIR) $opt->{'cflags'}";
if ($^O eq 'VMS') {
  $cflags = "\$(DBI_INSTARCH_DIR),$opt->{'cflags'}";
}
$cflags .= " -DDBD_MYSQL_WITH_SSL" if $opt->{'ssl'};
$cflags .= " -DDBD_MYSQL_INSERT_ID_IS_GOOD" if $DBI::VERSION > 1.42;
$cflags .= " -DDBD_NO_CLIENT_FOUND_ROWS" if $opt->{'nofoundrows'};
$cflags .= " -g ";
my %o = ( 'NAME' => 'DBD::mysql',
	  'INC' => $cflags,
	  'dist'         => { 'SUFFIX'       => ".gz",
			      'DIST_DEFAULT' => 'all installhtml tardist',
			      'COMPRESS'     => "gzip -9f" },
	  'clean' => { 'FILES' => '*.xsi' },
		'realclean' => { 'FILES' => 't/mysql.mtest' },
          'C' => ["dbdimp.c", "mysql.c"],
          'XS' => {'mysql.xs' => 'mysql.c'},
	  'OBJECT' => '$(O_FILES)',
	  'LIBS' => $opt->{'libs'},
	  $opt->{'ldflags'} ? ('LDFLAGS' => $opt->{'ldflags'}) : (),
	  'VERSION_FROM' => 'lib/DBD/mysql.pm'
	);

my %embedded_files=();

if ($opt->{'embedded'})
{

 %embedded_files = ( 'mysql.xs' => { filename  => 'mysqlEmb/mysqlEmb.xs',
                                       replace   => { ':mysql'    => ':mysqlEmb',
                                                      'mysql.xsi' => 'mysqlEmb.xsi'},
                                       makedir => 'mysqlEmb'
                                     },
                       'lib/DBD/mysql.pm' => { filename => 'mysqlEmb/lib/DBD/mysqlEmb.pm',
                                               replace  => { ':mysql'   => ':mysqlEmb',
                                                    '=> \'mysql\'' => '=> \'mysqlEmb\''},
                                               makedir => 'mysqlEmb/lib/DBD'
                                             },
                       'lib/DBD/mysql/GetInfo.pm' => { filename => 'mysqlEmb/lib/DBD/mysqlEmb/GetInfo.pm',
                                                       replace => {':mysql'   => ':mysqlEmb',
                                                    '\'mysql\'' => '\'mysqlEmb\''},
                                                       makedir => 'mysqlEmb/lib/DBD/mysqlEmb'
                                                     },
                       't/mysql.dbtest' => { filename => 'mysqlEmb/t/mysqlEmb.dbtest',
                                             makedir => 'mysqlEmb/t' 
                                           },
                       't/mysql.mtest' => { filename => 'mysqlEmb/t/mysqlEmb.mtest',
                                             makedir => 'mysqlEmb/t',
                                             replace =>  { 'DBI:mysql'=> 'DBI:mysqlEmb', 
                                                            'test_db";' => 'test_db;mysql_embedded_options=--datadir=./t,--skip-innodb,--skip-bdb";'
                                                         }
                                           },
                       't/lib.pl' => { filename => 'mysqlEmb/t/lib.pl',
                                       replace =>  { '\$mdriver =.*' => "\$mdriver =\'mysqlEmb\';"},
                                       makedir => 'mysqlEmb/t'
                                    },
                       't/20createdrop.t' => { filename => 'mysqlEmb/t/20createdrop.t',
                                               makedir => 'mysqlEmb/t'
                                             },
                       't/30insertfetch.t' => { filename => 'mysqlEmb/t/30insertfetch.t',
                                                makedir => 'mysqlEmb/t'
                                              },
                       't/40bindparam.t' => { filename => 'mysqlEmb/t/40bindparam.t',
                                              makedir => 'mysqlEmb/t'
                                             },
                       't/40blobs.t' => { filename => 'mysqlEmb/t/40blobs.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/40listfields.t' => { filename => 'mysqlEmb/t/40listfields.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/40nulls.t' => { filename => 'mysqlEmb/t/40nulls.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/40numrows.t' => { filename => 'mysqlEmb/t/40numrows.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/50chopblanks.t' => { filename => 'mysqlEmb/t/50chopblanks.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/50commit.t' => { filename => 'mysqlEmb/t/50commit.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/60leaks.t' => { filename => 'mysqlEmb/t/60leaks.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },
                       't/00base.t' => { filename => 'mysqlEmb/t/00base.t',
                                                                    makedir => 'mysqlEmb/t'
                                                                  },

                       'myld' => { filename => 'mysqlEmb/myld',
                                   makedir => 'mysqlEmb'
                                 },
                       'dbdimp.c' => { filename => 'mysqlEmb/dbdimp.c',
                                   makedir => 'mysqlEmb'
                                 },
                       'dbdimp.h' => { filename => 'mysqlEmb/dbdimp.h',
                                   makedir => 'mysqlEmb'
                                 },
                       'constants.h' => { filename => 'mysqlEmb/constants.h',
                                   makedir => 'mysqlEmb'
                                 },
                       'Makefile.PL.embedded' => { filename => 'mysqlEmb/Makefile.PL',
                                   makedir => 'mysqlEmb'
                                 },
            );


  #Create embedded files from original ones
  prepare_files(\%embedded_files);

  my %e=%o;

  $o{'clean'}->{'FILES'} .= " ./mysqlEmb";
  $o{'DIR'}=['mysqlEmb'];

  $e{'NAME'} = 'DBD::mysqlEmb';
  $e{'C'} = ["dbdimp.c", "mysqlEmb.c"];
  $e{'XS'} = {'mysqlEmb.xs' => 'mysqlEmb.c'};
  $e{'VERSION_FROM'} = 'lib/DBD/mysqlEmb.pm';
  $e{'LIBS'} = $opt->{'embedded'};

  $e{'INC'} .= " -DDBD_MYSQL_EMBEDDED";

  print "Preparing embedded Makefile\n";

  #Create Makefile.conf for mysqlEmb Makefile.PL
  create_makefile(Data::Dumper->Dump([\%e], ["o"]));

}

if ($ExtUtils::MakeMaker::VERSION >= 5.43) {
  $o{'CAPI'} = 'TRUE'
    if ($ExtUtils::MakeMaker::VERSION >= 5.43
	&&  $Config::Config{'archname'} =~ /-object\b/i);
  $o{'AUTHOR'} = 'Rudy Lippan <rlippan@remotelinux.com>';
  $o{'ABSTRACT'} =
    'A MySQL driver for the Perl5 Database Interface (DBI)';
  $o{'PREREQ_PM'} = { 'DBI' => 1.08,
		      'Data::Dumper' => 0 };
  %o=(%o,
    LICENSE => 'perl',
    MIN_PERL_VERSION => '5.005',
    META_MERGE => {
      resources => {
        repository => 'https://github.com/CaptTofu/DBD-mysql',
      },
    },
    BUILD_REQUIRES => { 'Test::More' => 0,
    },
    CONFIGURE_REQUIRES => { 'DBI' => 1.08,
    },
  );
}

WriteMakefile1(%o);
exit 0;


############################################################################
#
#   Name:    Usage
#
#   Purpose: Print Usage message and exit with error status.
#
############################################################################

sub Usage {
  print STDERR <<"USAGE";
Usage: perl $0 [options]

Possible options are:

  --cflags=<flags>       Use <flags> for running the C compiler; defaults
                         to the value of "mysql_config --cflags" or a guessed
                         value
  --libs=<libs>          Use <libs> for running the linker; defaults
                         to the value of "mysql_config --libs" or a gussed
                         value
  --force-embedded       Build version of driver supporting mysqlEmb
  --embedded=<libs>      Use these libs when building the embedded version of
                         DBD (with --force-embedded). Defaults to the value of
                         "mysql_config --embedded".
  --testdb=<db>          Use the database <db> for running the test suite;
                         defaults to $TESTDB
  --testuser=<user>      Use the username <user> for running the test suite;
                         defaults to no username
  --testpassword=<pwd>   Use the password <pwd> for running the test suite;
                         defaults to no password
  --testhost=<host>      Use <host> as a database server for running the
                         test suite; defaults to localhost.
  --testport=<port>      Use <port> as the port number of the database;
                         by default the port number is choosen from the
                         mysqlclient library
  --mysql_config=<path>  Specify <path> for mysql_config script
  --with-mysql=<path>    Specify <path> for the root of the MySQL installation.
  --nocatchstderr        Supress using the "myld" script that redirects
                         STDERR while running the linker.
  --nofoundrows          Change the behavior of \$sth->rows() so that it
  			 returns the number of rows physically modified 
			 instead of the rows matched
  --ps-protocol          Toggle the use of driver emulated prepared statements
                         prepare, requires MySQL server >= 4.1.3 for
                         server side prepared statements, off by default 
  --bind-type-guessing   Toggle the use of driver attribute mysql_bind_type_guessing 
                         This feature makes it so driver-emulated prepared statements
                         try to "guess" if a value being bound is numeric, in which 
                         case, quotes will not be put around the value.
  --ssl			         Enable SSL support
  --help                 Print this message and exit

All options may be configured on the command line. If they are
not present on the command line, then mysql_config is called (if
it can be found):

  mysql_config --cflags
  mysql_config --libs
  mysql_config --embedded
  mysql_config --testdb

and so on. See the INSTALL.html file for details.
USAGE
  exit 1;
}


############################################################################
#
#   Name:    Configure
#
#   Purpose: Automatic configuration
#
#   Inputs:  $param - Name of the parameter being configured
#
#   Returns: Generated value, never undef
#
############################################################################

sub Configure {
    my($opt, $source, $param) = @_;

    if ($param eq 'bind-type-guessing') {
        $source->{$param}= ($opt->{$param}) ? "User's choice" : 'default';
        return;
    }
    if ($param eq 'ps-protocol') {
        $source->{$param}= ($opt->{$param}) ? "User's choice" : 'default';
        return;
    }
    if (exists($opt->{$param})) {
        $source->{$param} = "User's choice";
        return;
    }

# First try to get options values from mysql_config
    my $command = $opt->{'mysql_config'} . " --$param";
    eval 
    {
        open(PIPE, "$command |") or die "Can't find mysql_config.";
    };

    if (!$@) {
        my $str = "";
        while (defined(my $line = <PIPE>)) { $str .= $line; }

        if ($str ne ""  &&  $str !~ /Options:/) {
            $str =~ s/\s+$//s;
            $str =~ s/^\s+//s;

            # Unfortunately ExtUtils::MakeMaker doesn't deal very well
            # with -L'...'
            $str =~ s/\-L\'(.*?)\'/-L$1/sg;
            $str =~ s/\-L\"(.*?)\"/-L$1/sg;

            # Separate libs from ldflags
            if ($param eq 'libs') {
                my (@libs, @ldflags);
                for (split ' ', $str) {
                    if (/^-[Ll]/) { push @libs, $_ }
                    else          { push @ldflags, $_ }
                }
                $str = "@libs";
                $opt->{ldflags} = "@ldflags";
                $source->{ldflags} = "mysql_config";
            }

            $opt->{$param} = $str;
            $source->{$param} = "mysql_config";
            return;
        }
    }
    else {
        print "Can't find mysql_config. Use --mysql_config option to specify where mysql_config is located\n";
    }

# Ok, mysql_config doesn't work. We need to do our best
# First check environment variables
    if (defined($ENV{'DBD_MYSQL_'.uc($param)})) {
        $opt->{$param} = $ENV{'DBD_MYSQL_'.uc($param)};
        $source->{$param} = 'environment';
    }

    # Then try to guess
    unless ($opt->{$param}) {
      if ($param eq 'testuser') {
        my $user = $ENV{USER} || '';
        print "

PLEASE NOTE:

For 'make test' to run properly, you must ensure that the 
database user '$user' can connect to your MySQL server 
and has the proper privileges that these tests require such 
as 'drop table', 'create table', 'drop procedure', 'create procedure'
as well as others. 

mysql> grant all privileges on test.* to '$user'\@'localhost' identified by 's3kr1t';

You can also optionally set the user to run 'make test' with:

perl Makefile.PL --testuser=username

";
      $opt->{$param} = $user;
	  $source->{$param} = 'guessed';
    }
    elsif ($param eq "nocatchstderr" || $param eq "nofoundrows") {
      $source->{$param} = "default";
      $opt->{$param} = 0;
    }
    elsif ($param eq "testdb") {
      $source->{$param} = "default";
      $opt->{$param} = $TESTDB;
    }
    elsif ($param eq "testhost" || $param eq "testport"  ||  
        $param eq "testpassword" || $param eq "testsocket" ) {
      $source->{$param} = "default";
      $opt->{$param} = "";
    }
    elsif($param eq 'force-embedded') {
      $source->{$param} = $opt->{$param} ? "default" : 'not set';
    }
    elsif ($param eq "cflags") {
      $source->{$param} = "guessed";
      my $dir = SearchFor('include', 'mysql.h');
      if ($dir) {
        $opt->{$param} = "-I$dir";
        return;
      }
      die <<"MSG";
Failed to determine directory of mysql.h. Use

  perl Makefile.PL --cflags=-I<dir>

to set this directory. For details see the INSTALL.html file,
section "C Compiler flags" or type

  perl Makefile.PL --help
MSG
    }
    elsif ($param eq "libs" || $param eq "embedded") {
      $source->{$param} = "guessed";

      if ($param eq "embedded" && !$opt->{'embedded'}) {
        $opt->{$param}="";
        return;
      }

      my @files=();
      my $default_libs;
      if ($param eq "embedded") {
        $default_libs= "-lmysqld -lpthread -lz -lm -lcrypt -lnsl";
        @files = ($^O =~ /mswin32/i) ? qw(mysqlclient.lib) :
		  	qw(libmysqld.a);
      }
      else {
        $default_libs= "-lmysqlclient -lz -lm -lcrypt -lnsl";
        @files = ($^O =~ /mswin32/i) ? qw(mysqlclient.lib) :
	  		qw(libmysqlclient.a libmysqlclient.so);
      }

      my $dir = SearchFor('lib', @files);

      if ($dir) {
          $opt->{$param} = "-L$dir $default_libs";
        return;
      }
      my $f = join("|", @files);
      die <<"MSG";
Failed to determine directory of $f. Use

  perl Makefile.PL "--$param=-L<dir> $default_libs"

to set this directory. For details see the INSTALL.html file,
section "Linker flags" or type

  perl Makefile.PL --help
MSG
    } 
    elsif ($param eq "ssl") {
      $opt->{$param} = ($opt->{"libs"} =~ /ssl/) ? 1 : 0;
      $source->{$param} = "guessed";
    } 
    else {
      die "Unknown configuration parameter: $param";
    }
  }
}

my $haveFileSpec;
my $fineDir;
sub SearchFor {
  my($subdir, @files) = @_;
  $haveFileSpec = eval { require File::Spec } unless defined($haveFileSpec);

  my @dirs = ($^O =~ /mswin32/i) ? qw(C:) : qw(/usr/local /usr /opt);
  unshift(@dirs, $fineDir) if defined($fineDir);

  for my $f (@files) {
    for my $dir (@dirs) {
      my $try1 = $haveFileSpec ?
	File::Spec->catdir($dir, $subdir) : "$dir/$subdir";
      my $try2 = $haveFileSpec ?
	File::Spec->catdir($dir, "mysql") : "$dir/mysql";
      my $try3 = $haveFileSpec ?
	File::Spec->catdir($try1, "mysql") : "$try1/mysql";
      my $try4 = $haveFileSpec ?
	File::Spec->catdir($try2, $subdir) : "$try2/$subdir";
      for my $path ($try3, $try4, $try2, $try1, $dir) {
	my $file = $haveFileSpec ?
	  File::Spec->catfile($path, $f) : "$path/$f";
	if (-f $file) {
	  $fineDir = $dir;
	  return $path;
	}
      }
    }
  }
}

sub SearchFor2 {
  my($files, $dirs) = @_;

  for my $f (@{$files}) 
  {
    for my $dir (@{$dirs}) 
    {
      my $file = $haveFileSpec ?  File::Spec->catfile($dir, $f) : "$dir/$f";
      if (-f $file) 
      {
        $fineDir = $dir;
        return $dir;
      }
    }
  }
}


sub check_include_version {
  
  my ($dir, $ver) = @_;

  my $headerfile;

  $dir =~ s/-I//;
  $dir =~ s/'//g;
  $dir =~ s/\s.*//g;

  open(HEADERFILE ,"<${dir}/mysql_version.h") or
  (print "Unable to open header file ${dir}/mysql_version.h" && exit(0));
  {
    local undef $/;
    $headerfile = <HEADERFILE>;
  }
  close(HEADERFILE);

  my ($version_id) = ($headerfile =~ /MYSQL_VERSION_ID[\t\s]+(\d+)[\n\r]/);

  if ($version_id < $ver)
  {
    print  <<"MSG";

Version of MySQL include files in $dir - $1
MSG
    return 0;
  }
  return 1;
}

sub replace
{
  my ($str, $ref)=@_;

  for my $find (keys %{$ref})
  {
    $str =~ s/$find/$ref->{$find}/g;
  }
  $str;
}

sub prepare_files
{
  my ($files)= @_;
  my $line;
  my @lib;

  for my $file (keys %{$files})
  {

    if ($files->{$file}->{makedir})
    {
      mkpath $files->{$file}->{makedir} or die "Can't create dir $files->{$file}->{makedir}"
      unless (-e $files->{$file}->{makedir} && -d $files->{$file}->{makedir});
    }

    my $replace=$files->{$file}->{replace};

    if ($replace)
    {
       open(FILE, $file) or die "Can't open file $file";
       @lib= map { $replace ? replace($_, $replace) : $_; }  <FILE>;
       close(FILE);

       open(FILE, ">".$files->{$file}->{filename}) or die "Can't open file $files->{$file}->{filename}";
       print FILE @lib;
       close(FILE);
    }
    else
    {
       if(!copy($file, $files->{$file}->{filename}))
       {
         die "Unable to copy $file to $files->{$file}->{filename}\n";
       }
    }
  }
}

sub create_makefile
{
  my ($cnf)=@_;

  open(LOG, ">mysqlEmb/Makefile.conf") or die "Can't write to file mysqlEmb/Makefile.conf";
  print LOG $cnf;
  close(LOG);
}

sub win32_mysql_config {
	my ($mysql_dir) = @_;
	my $mysqladmin;
	
	if ($mysql_dir) {
	  unless (-d $mysql_dir) {
		die qq{"$mysql_dir" does not exist};
	  }
	  $mysqladmin = File::Spec->catfile($mysql_dir, 'bin', 'mysqladmin.exe');
	  unless (-f $mysqladmin) {
		die qq{"bin/mysqladmin.exe" not found under "$mysql_dir"};
	  }
	}

	my (@path_ext) = path_ext();
	unless ($mysqladmin) {
	  $mysqladmin = which('mysqladmin', @path_ext);
	  unless ($mysqladmin) {
		die << 'DEATH';
mysqladmin.exe was not found in your PATH.
Please either add the directory containing mysqladmin.exe
to your PATH environment variable, or rerun this script
with the --with-mysql=C:\Path\to\Mysql option, giving the
root directory of your MySQL installation.
DEATH
	  }
	  ($mysql_dir = dirname($mysqladmin)) =~ s{[/\\]bin[/\\]?$}{};
	}

	my $basedir = Win32::GetShortPathName($mysql_dir);
	my $ldata = File::Spec->catdir($basedir, 'data');
	my $execdir = File::Spec->catdir($basedir, 'bin');
	my $bindir = File::Spec->catdir($basedir, 'bin');
	my $pkglibdir= File::Spec->catdir($basedir, 'lib', 'opt');
	my $pkgincludedir = File::Spec->catdir($basedir, 'include');
	my $ldflags = '';
	my $client_libs = $Config{'cc'} eq 'gcc' ? '-lmysql -lzlib' : '-lmysqlclient -lzlib';

	if (($Config{'_a'} eq '.a') and (! -e File::Spec->catfile($pkglibdir, 'libmysql.a'))) {
		# This is done because ExtUtils::Liblist expects .a files, not .lib files.
		copy(File::Spec->catfile($pkglibdir, 'libmysql.lib'), File::Spec->catfile($pkglibdir, 'libmysql.a'));
		copy(File::Spec->catfile($pkglibdir, 'zlib.lib'), File::Spec->catfile($pkglibdir, 'libzlib.a'));
	}
	
	$mysqladmin = Win32::GetShortPathName($mysqladmin);
    my $v;
    if ( defined $opt->{'testuser'} and defined $opt->{'testpassword'}) {
        $v = qx( sprintf('%s --user=%s --password=%s version', $mysqladmin , $opt->{'testuser'}, $opt->{'testpassword'}) );
    } else {
        $v = qx($mysqladmin version);
    }
	unless ($v) {
	  print STDERR "Problem running $mysqladmin - aborting ...\n";
	  exit(1);
	}

	my ($version, $port);
	if ($v =~ /Server version\s+(.*?)\n/m) {
	  $version = $1;
	}
	if ($v =~ /TCP port\s+(.*?)\n/m) {
	  $port = $1;
	}

	my $libs = qq{$ldflags -L"$pkglibdir" $client_libs};
	my $cflags = qq{-I"$pkgincludedir"};
	my $embedded_libs = qq{$ldflags -L"$pkglibdir"};

	my $license = <<'EOL';
# Copyright (C) 2005 MySQL AB & MySQL Finland AB & TCX DataKonsult AB
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# This script reports various configuration settings that may be needed
# when using the MySQL client library.
EOL

	my $mysql_config = File::Spec->catfile($basedir, 'bin', 'mysql_config.pl');
	open(my $fh, '>', $mysql_config)
	  or die "Cannot open $mysql_config for writing: $!";

	print $fh <<"EOL";
#!$^X
use strict;
use warnings;
use Getopt::Long;

$license

my \$basedir = q{$basedir};
my \$ldata = q{$ldata};
my \$execdir = q{$execdir};
my \$bindir = q{$bindir};
my \$pkglibdir = q{$pkglibdir};
my \$pkgincludedir = q{$pkgincludedir};
my \$ldflags = q{$ldflags};
my \$client_libs = q{$client_libs};
my \$version = q{$version};
my \$port = q{$port};
my \$libs = q{$libs};
my \$cflags = q{$cflags};
my \$embedded_libs = q{$embedded_libs};
EOL

	while (<DATA>) {
	  print $fh $_;
	}
	close $fh;
	my @args = ('pl2bat', $mysql_config);
	system(@args) == 0 or die "System @args failed: $?";

	print << "END";

mysql_config.pl, and an associated bat file, has been 
successfully created under
   $basedir\\bin

END

	return;
}

sub path_ext {
  my @path_ext;

  if ($ENV{PATHEXT}) {
    push @path_ext, split ';', $ENV{PATHEXT};
    for my $ext (@path_ext) {
      $ext =~ s/^\.*(.+)$/$1/;
    }
  }
  else {
    #Win9X: doesn't have PATHEXT
    push @path_ext, qw(com exe bat);
  }
  
  return @path_ext;
}

sub which {
  my $program = shift;
  my @path_ext = @_;
  return unless $program;
  my @a = map {File::Spec->catfile($_, $program) } File::Spec->path();
  for my $base (@a) {
    return $base if -x $base;
    for my $ext (@path_ext) {
      return "$base.$ext" if -x "$base.$ext";
    }
  }
  return;
}

package MY;

sub libscan {
    my($self, $path) = @_;
    return '' if $path =~ /\B\.svn\b|~#|\BSCCS\b/;
    $path;
}

sub macro {
  "\n" . DBI::DBD::dbd_postamble(@_) . <<"POSTAMBLE";

installhtml: lib/DBD/mysql/INSTALL.pod
\tpod2html --infile=lib/DBD/mysql/INSTALL.pod --outfile=INSTALL.html

POSTAMBLE
};

sub dynamic_lib {
  my $self = shift;
  my $result = $self->SUPER::dynamic_lib(@_);
  if (!$::opt->{nocatchstderr}  &&  $result =~ /\$\(LD\)/) {
    $result =~ s/(\$\(LD\))/\$\(PERL\) myld \$(LD)/sg;
  }
  return $result;
}

package main;



sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
  my %params=@_;
  my $eumm_version=$ExtUtils::MakeMaker::VERSION;
  $eumm_version=eval $eumm_version;
  die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
  die "License not specified" if not exists $params{LICENSE};
  if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
    #EUMM 6.5502 has problems with BUILD_REQUIRES
    $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
    delete $params{BUILD_REQUIRES};
  }
  delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
  delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
  delete $params{META_MERGE} if $eumm_version < 6.46;
  delete $params{META_ADD} if $eumm_version < 6.46;
  delete $params{LICENSE} if $eumm_version < 6.31;
  delete $params{AUTHOR} if $] < 5.005;
  delete $params{ABSTRACT_FROM} if $] < 5.005;
  delete $params{BINARY_LOCATION} if $] < 5.005;

  ExtUtils::MakeMaker::WriteMakefile(%params);
}
__DATA__

my %opts = ();
GetOptions(\%opts,
           'cflags',
           'libs',
           'port',
           'version',
           'libmysqld-libs',
           'embedded',
           'embedded-libs',
           'help',
          ) or usage();

usage() if ($opts{help} or not %opts);

SWITCH : {
  local $\ = "\n";
  $opts{cflags} and do {
    print $cflags;
    last SWITCH;
  };
  $opts{libs} and do {
    print $libs;
    last SWITCH;
  };
  $opts{port} and do {
    print $port;
    last SWITCH;
  };
  $opts{version} and do {
    print $version;
    last SWITCH;
  };
  ($opts{'libmysqld-libs'} or $opts{embedded} or $opts{'libmysqld-libs'} )
    and do {
      print $embedded_libs;
      last SWITCH;
    };
  usage();
}

exit(0);

sub usage {
  print << "EOU";
Usage: $0 [OPTIONS]

Options:
        --cflags         [$cflags]
        --libs           [$libs]
        --port           [$port]
        --version        [$version]
	--libmysqld-libs [$embedded_libs]
EOU
    exit(1);
}




