#!/usr/bin/perl
###########################################################################
# Makefile for Java API Compliance Checker
# Install/remove the tool for GNU/Linux, FreeBSD and Mac OS X
#
# Copyright (C) 2011-2018 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301  USA.
###########################################################################
use strict;
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");
use File::Path qw(mkpath rmtree);
use File::Spec qw(catfile file_name_is_absolute);
use File::Copy qw(copy);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use File::Find;
use Config;

my $TOOL_SNAME = "japi-compliance-checker";
my $ARCHIVE_DIR = abs_path(dirname($0));

my $HELP_MSG = "
NAME:
  Makefile for Java API Compliance Checker

DESCRIPTION:
  Install $TOOL_SNAME command and private modules.

USAGE:
  sudo perl $0 -install -prefix /usr
  sudo perl $0 -remove -prefix /usr

OPTIONS:
  -h|-help
      Print this help.

  --prefix=PREFIX
      Install files in PREFIX [/usr].

  -install
      Command to install the tool.

  -remove
      Command to remove the tool.

EXTRA OPTIONS:
  --destdir=DESTDIR
      This option is for maintainers to build
      RPM or DEB packages inside the build root.
      The environment variable DESTDIR is also
      supported.
\n";

if(not @ARGV)
{
    print $HELP_MSG;
    exit(0);
}

my ($PREFIX, $DESTDIR, $Help, $Install, $Remove);

GetOptions(
    "h|help!" => \$Help,
    "prefix=s" => \$PREFIX,
    "destdir=s" => \$DESTDIR,
    "install!" => \$Install,
    "remove!" => \$Remove
) or exit(1);

sub scenario()
{
    if($Help)
    {
        print $HELP_MSG;
        exit(0);
    }
    if(not $Install and not $Remove)
    {
        print STDERR "ERROR: command is not selected (-install or -remove)\n";
        exit(1);
    }
    
    if($Install)
    { # remove old version first
        $Remove = 1;
    }
    
    if($PREFIX ne "/") {
        $PREFIX=~s/[\/]+\Z//g;
    }
    if(not $PREFIX)
    { # default prefix
        if($Config{"osname"}!~/win/i) {
            $PREFIX = "/usr";
        }
    }
    if(my $Var = $ENV{"DESTDIR"})
    {
        print "Using DESTDIR environment variable\n";
        $DESTDIR = $Var;
    }
    if($DESTDIR)
    {
        if($DESTDIR ne "/") {
            $DESTDIR=~s/[\/]+\Z//g;
        }
        if(not isAbs($DESTDIR))
        {
            print STDERR "ERROR: destdir is not absolute path\n";
            exit(1);
        }
        $PREFIX = $DESTDIR.$PREFIX;
    }
    else
    {
        if(not isAbs($PREFIX))
        {
            print STDERR "ERROR: prefix is not absolute path\n";
            exit(1);
        }
    }
    
    if($Install)
    {
        if(not -d $PREFIX) {
            mkpath($PREFIX);
        }
        elsif(not -w $PREFIX)
        {
            print STDERR "ERROR: you should be root\n";
            exit(1);
        }
    }
    
    print "INSTALL PREFIX: $PREFIX\n";
    
    # paths
    my $EXE_PATH = catFile($PREFIX, "bin");
    my $MODULES_PATH = catFile($PREFIX, "share", $TOOL_SNAME);
    my $REL_PATH = catFile("..", "share", $TOOL_SNAME);
    my $TOOL_PATH = catFile($EXE_PATH, $TOOL_SNAME);
    
    if($Remove)
    {
        if(-e $EXE_PATH."/".$TOOL_SNAME)
        { # remove executable
            print "-- Removing $TOOL_PATH\n";
            unlink($EXE_PATH."/".$TOOL_SNAME);
        }
        elsif(not $Install) {
            print "The tool is not installed\n";
        }
        
        if(-d $MODULES_PATH)
        { # remove modules
            print "-- Removing $MODULES_PATH\n";
            rmtree($MODULES_PATH);
        }
        elsif(not $Install) {
            print "The modules of the tool are not installed\n";
        }
    }
    if($Install)
    {
        # configure
        my $Content = readFile($ARCHIVE_DIR."/".$TOOL_SNAME.".pl");
        if($DESTDIR) { # relative path
            $Content=~s/MODULES_INSTALL_PATH/$REL_PATH/;
        }
        else { # absolute path
            $Content=~s/MODULES_INSTALL_PATH/$MODULES_PATH/;
        }
        
        # copy executable
        print "-- Installing $TOOL_PATH\n";
        mkpath($EXE_PATH);
        writeFile($EXE_PATH."/".$TOOL_SNAME, $Content);
        chmod(0755, $EXE_PATH."/".$TOOL_SNAME);
        
        if($Config{"osname"}=~/win/i) {
            writeFile($EXE_PATH."/".$TOOL_SNAME.".cmd", "\@perl \"$TOOL_PATH\" \%*");
        }
        
        # copy modules
        if(-d $ARCHIVE_DIR."/modules")
        {
            print "-- Installing $MODULES_PATH\n";
            mkpath($MODULES_PATH);
            copyDir($ARCHIVE_DIR."/modules", $MODULES_PATH);
        }
        
        if(not $DESTDIR)
        { # check PATH
            my $Warn = "WARNING: your PATH variable doesn't include \'$EXE_PATH\'\n";
            
            if($Config{"osname"}=~/win/i)
            {
                if($ENV{"PATH"}!~/(\A|[:;])\Q$EXE_PATH\E[\/\\]?(\Z|[:;])/i) {
                    print $Warn;
                }
            }
            else
            {
                if($ENV{"PATH"}!~/(\A|[:;])\Q$EXE_PATH\E[\/\\]?(\Z|[:;])/) {
                    print $Warn;
                }
            }
        }
    }
    exit(0);
}

sub catFile(@) {
    return File::Spec->catfile(@_);
}

sub isAbs($) {
    return File::Spec->file_name_is_absolute($_[0]);
}

sub copyDir($$)
{
    my ($From, $To) = @_;
    my %Files;
    find(\&wanted, $From);
    sub wanted {
        $Files{$File::Find::dir."/$_"} = 1 if($_ ne ".");
    }
    foreach my $Path (sort keys(%Files))
    {
        my $Inst = $Path;
        $Inst=~s/\A\Q$ARCHIVE_DIR\E/$To/;
        if(-d $Path)
        { # directories
            mkpath($Inst);
        }
        else
        { # files
            mkpath(dirname($Inst));
            copy($Path, $Inst);
        }
    }
}

sub readFile($)
{
    my $Path = $_[0];
    
    open(FILE, $Path) || die ("can't open file \'$Path\': $!\n");
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    
    return $Content;
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    
    open(FILE, ">".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

scenario();
