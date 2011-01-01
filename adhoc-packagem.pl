#!/usr/bin/env perl

use warnings;
use strict;
use 5.010;
use File::Find;
use File::Copy;
use Cwd;

use constant {
	EXIT_OK => 0,
	EXIT_WRARG => 1,
	EXIT_CANTCONT => 2, # can't continue - unsupported OS or some other initial checks failed
	EXIT_ERRPROC => 3 # error during processing files
};

my $ext = "insfiles";
sub help {
	say "\"Ad hoc package manager\": this installs files from a source to \"root\" directory (/ by default)";
	say "and helps uninstalling them";
	say "for this purpose, a file .$ext is made";
	say "only contents of source directory are copied, not the directory itself";
	say "";
	say "if a file exists, it's not overridden - copying is aborted";
	say "*** and file modes are ignored ***";
	say "";
	say "args: inst source_dir [root_path]";
	say "or: rm anything.$ext [root_path]";
	say "example: $0 inst stuff";
	say "example 2: $0 rm stuff.$ext";
	say "";
	say "warning: it's not designed to be completely error-prone";
	say "esp. if one gives wrong args (source or destination)";
	# files with \n in name? `.' or anything wrong as src/dest? the same REAL src/dest?
	say "\nauthor: Enlik";
}

my $inst; # 0 or 1
my $source;
my $root; # absolute path, with a / at the end
my $ff_fh;
my $ff;

if ($^O ne "linux") {
	say "Sorry, your OS may not be supported.";
	say "If it has Linux-like path naming convension, remove this check";
	say "(you probably have a BSD or so, so you know how ;).)";
	exit EXIT_CANTCONT;
}

{
	my ($oper, $_source, $_root) = @ARGV;
	$oper //= "";
	if ($oper eq "inst") {
		$inst = 1;
		unless (defined($_source)) {
			say "Error: you didn't provide source dir.";
			say "";
			help;
			exit EXIT_WRARG;
		}
		$source = $_source;
		$root = $_root // "/";
	}
	elsif ($oper eq "rm") {
		$inst = 0;
		unless (defined($_source)) {
			say "Error: you didn't provide a .$ext file.";
			say "";
			help;
			exit EXIT_WRARG;
		}
		$source = $_source;
		$root = $_root // "/";
	}
	else {
		say "Error: incorrect args.";
		say "";
		help;
		exit EXIT_WRARG;
	}
}


if ($inst) {
	do_inst();
}
else {
	do_rm();
}

#################################### inst ####################################

sub do_inst {
	# set $root absolute path
	unless (substr ($root,0,1) eq '/') {
		$root = Cwd::cwd . '/' . $root;
	}
	if ($source =~ /(.+?)\/+$/) { $source = $1 } # rstrip /s
	if ($root =~ /(.+?)\/+$/) { $root = $1 } # rstrip /s
	$root .= '/' unless $root eq '/'; # and prepend one
	if (! -d $source) {
		say "Error, source doesn't exist or is not a dir.";
		exit EXIT_CANTCONT;
	}
	if (! -d $root) {
		say "Error, destination $root doesn't exist or is not a dir.";
		exit EXIT_CANTCONT;
	}
	say "info: source is: $source";
	say "info: destination is: $root";
	$ff = $source . "." . $ext;
	if (-f $ff) {
		say "Error, file $ff already exists.";
		say "Have you already installed somewhere the files?";
		exit EXIT_CANTCONT;
	} 
	else {
		say ".$ext file is: $ff";
	}
	
	# chdir $source or die "Can't change dir to $source: $!\n";
	
	unless (open ($ff_fh, ">", $ff)) {
		say "Error, can't open .$ext file for writing.";
		exit EXIT_CANTCONT;
	}
	
	say $ff_fh "# $0";
	say $ff_fh "# this is a comment.";
	say $ff_fh "# $source -> $root";
	say $ff_fh "VERSION 1";
	say $ff_fh "ROOTDIR $root";
	find (\&process_file, $source) or exit EXIT_CANTCONT;
	close $ff_fh;
	say "\nDone. Remember to backup the file $ff.";
	exit EXIT_OK;
}

sub process_file {
	my $path = $File::Find::name;
	my $file = $_; # find does chdir by default, so we'll use this
	my $dir = $File::Find::dir;
	my $_path_without_source;
	my $dst_path; # = $root . $path;
	
	return if $file eq '.'; # omit 'dir' itself
	# say "**** cwd: " . Cwd::getcwd;say "p $path\nf $file\nd $dir\ndst $dst_path";
	if ($path eq $source) {
		say "The source and destination are the same, aborting.";
		exit EXIT_CANTCONT;
	}
	$_path_without_source = substr $path,(length ($source)+1);
	$dst_path = $root . $_path_without_source;

	if(-d $file) {
		if(-d $dst_path) {
			# OK, dir exists, we don't touch it
		}
		elsif(-e _) {
			say "Error! The file $dst_path exists and it's not a directory.";
			say "Aborting!";
			say "REMEMBER TO UNDONE CHANGES MANUALLY using $0 rm $ff";
			close $ff_fh;
			exit EXIT_ERRPROC; # with File::Find one can't abort find() it seems :/
		}
		else {
			unless (mkdir $dst_path) {
				say "Error! Can't create directory $dst_path - aborting!";
				say $!;
				say "REMEMBER TO UNDONE CHANGES MANUALLY using $0 rm $ff";
				close $ff_fh;
				exit EXIT_ERRPROC;
			}
			say $ff_fh "NEWDIR $dst_path";
		}
	}
	else {
		if(-d $dst_path) {
			say "Error! The file $dst_path exists and IS a directory,";
			say "but source file is not a directory. Aborting!";
			say "REMEMBER TO UNDONE CHANGES MANUALLY using $0 rm $ff";
			close $ff_fh;
			exit EXIT_ERRPROC;
		}
		elsif (-e _) {
			# let's yell a bit
			say "Error! The file $dst_path exists!";
			say "I'm not going to overwrite it. Aborting!";
			say "REMEMBER TO UNDONE CHANGES MANUALLY using $0 rm $ff";
			close $ff_fh;
			exit EXIT_ERRPROC;
		}
		else {
			# Do it!
			unless (copy $file, $dst_path) {
				say "Error! Can't copy file $path to $dst_path - aborting!";
				say $!;
				say "REMEMBER TO UNDONE CHANGES MANUALLY using $0 rm $ff";
				close $ff_fh;
				exit EXIT_ERRPROC;
			}
			say $ff_fh "NEWFILE $dst_path";
		}
	}
}

#################################### rm ####################################

sub do_rm {
	unless ($source =~ /.+\.\Q$ext\E$/) {
		say "The file should end with .$ext.";
		exit EXIT_WRARG;
	}
	unless (open $ff_fh, "<", $source) {
		say "I can't open $source for reading: $!.";
		exit EXIT_CANTCONT;
	}
	my @opers; # $opers[n] = { oper => NEW...,  path => ... }
	my $version;
	my $line = 0;
	my $rootdir; # unused, even not checked
	
	while (<$ff_fh>) {
		$line++;
		chomp;
		next if /^#/; # classic
		if($_ =~ /^VERSION (.+)/) {
			$version = $1;
			if($version != 1) {
				say "Error, wrong version! Maybe you have old tool?";
				say "Only file with VERSION 1 are supported.";
				say "$_ at line $line";
				exit EXIT_ERRPROC;
			}
		}
		elsif ($_ =~ /^(NEWFILE|NEWDIR) (.+)/) {
			unless ($version) {
				say "Error, no VERSION specified.";
				say "There should be a line VERSION (version).";
				say "at line $line";
				exit EXIT_ERRPROC;
			}
			push @opers, { oper => $1, path => $2 };
		}
		elsif ($_ =~ /^ROOTDIR (.+)/) {
			$rootdir = $1;
		}
		else {
			say "Parse error at line $line.";
			say "Wrong line is: $_.";
			exit EXIT_ERRPROC;
		}
	}
	
	@opers = reverse @opers;
	for (@opers) {
		if ($_->{oper} eq 'NEWFILE') {
			unless (unlink $_->{path}) {
				say "Warning: can't remove file $_->{path}.";
				say "\t$!";
			}
		}
		elsif ($_->{oper} eq 'NEWDIR') {
			unless (rmdir $_->{path}) {
				say "Warning: can't remove directory $_->{path}.";
				say "\t$!";
				say "\tMaybe it wasn't empty because anything was added";
				say "\tto it after using this tool.";
			}
		}
	}
	say "Done! You may remove $source if you want. Enjoy!";
}
