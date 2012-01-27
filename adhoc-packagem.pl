#!/usr/bin/env perl

use warnings;
use strict;
use 5.010;
use File::Find;
use File::Copy;
use File::Spec;
use Cwd;

use constant {
	EXIT_OK => 0,
	EXIT_WRARG => 1,
	EXIT_CANTCONT => 2, # can't continue: unsupported OS or some other initial checks failed
	EXIT_ERRPROC => 3 # error during processing files
};

my $ext = "insfiles";
sub usage {
	my $ishelp = shift;
	# inst [-p|-dummy] /home/x/bash [-r /tmp] [-file insfile] [-nco] [-sc]
	# del [-p] insfile [-r /tmp]
	say "usage: inst [-p|-dummy] <source_dir> ",
		"[-r <root_path>] [-file <output>[.$ext]] [-nco] [-sc] [-strip]";
	say "or:    del [-p] <input>.$ext [-r <root_path>]";
	say "or:    [-h|--help]";
	say "";
	say "examples:";
	say "a)  $0 inst /tmp/lxdm -file /home/me/file";
	say "    will install (copy) stuff from /tmp/lxdm to / and create file ",
		"/home/me/file.$ext";
	say "b)  $0 inst -p /tmp/lxdm -r /mnt/abc/usr";
	say "    (run in pretend mode) will check if conflicts would occur while ",
		"installing\n     stuff from /tmp/lxdm to /mnt/abc/usr and create file ",
		"/tmp/lxdm.$ext";
	say "c)  $0 del /tmp/lxdm.$ext -r /";
	say "    will remove stuff as described in /tmp/lxdm.$ext; it's the same as";
	say "    \"$0 del /tmp/lxdm.$ext\" because / is default root directory";
	say "";
	say "-p     \tpretend mode";
	say "-dummy \tdummy mode (only create a .$ext file)";
	say "-nco   \tno change ownership";
	say "-sc    \tskip item on conflict";
	say "-strip \t\"strip\" root (destination) path from a .$ext file";
	say "\n(For details about usage (and other informations) see the file \"docs\".)";
	say "Use --help to get some more info." unless defined $ishelp;
}

sub help {
	say "\"Ad hoc package manager\": this installs files from a source to \"root\"";
	say "directory (/ by default) and helps uninstalling them.";
	say "For this purpose, a file .$ext is made.";
	say "Only contents of source directory are copied, not the directory itself.";
	say "";
	say "With \"inst\" if a file exists, it's not overridden - copying is aborted.";
	say "";
	say "In pretend mode (-p) no files are copied or removed, but with \"inst\"";
	say "command an .$ext file is written as it would be, and with \"del\"";
	say "command the list of files and directories with be printed, with the";
	say "information whether they still exist or not.";
	say "";
	say "Warning: it's not designed to be completely error-prone";
	say "esp. if one gives wrong args (source or destination).";
	say "";
	# files with \n in name? `.' or anything wrong as src/dest? the same src/dest?
	# ./adhoc-packagem.pl inst x -file x/blah -r y -> creates empty y/blah.$ext
	say "author: Enlik";
	say "";
	usage 1;
}

my $inst; # 0 or 1
my $pretend = 0; # 0 or 1
my $dummy = 0; # 0 or 1
my $change_ownership = 1; # 0 or 1
my $skip_on_conflict = 0; # 0 or 1
my $strip_root = 0; # 0 or 1
my $source;
my @source_a;
my $root; # absolute destination path
my @root_a;
my $ff_fh;
my $ff; # .$ext file

# 0 or 1; indicates if anything was copied (or would be in pretend mode)
my $changes_done = 0;
my $start_cwd = Cwd::cwd;

if ($^O ne "linux") {
	say "Sorry, your OS may not be supported.";
	say "If it has Linux-like path naming convension, remove this check";
	say "(you probably have a BSD or so, so you know how ;).)";
	exit EXIT_CANTCONT;
}

parse_cmdline();

if($pretend) {
	say "Running in \"pretend\" mode.";
}
if ($dummy) {
	say "Running in \"dummy\" mode.";
}

if ($inst) {
	do_inst();
}
else {
	do_del();
}

#################################### inst ####################################

sub do_inst {
	# set $root as absolute path
	$root = File::Spec->rel2abs($root);
	$source = File::Spec->canonpath($source);
	# we don't want volume names
	$root =   ( File::Spec->splitpath( $root,   "dirs" ) )[1];
	$source = ( File::Spec->splitpath( $source, "dirs" ) )[1];
	if (! -d $source) {
		say "Error, source \"$source\" doesn't exist or is not a dir.";
		exit EXIT_CANTCONT;
	}
	if (! -d $root) {
		say "Error, destination $root doesn't exist or is not a dir.";
		exit EXIT_CANTCONT unless $dummy;
	}
	@source_a = File::Spec->splitdir($source);
	@root_a   = File::Spec->splitdir($root);
	say "info: source is: $source";
	say "info: destination is: $root";
	unless ($change_ownership) {
		say "info: ownership of copied files will not be altered (-nco option ",
			"specified)";
	}
	if (defined $ff) { # user provided his own
		$ff .= "." . $ext unless $ff =~ /.+\.\Q$ext\E$/
	}
	else {
		my @dirs = @source_a;
		my $last = $dirs[-1];
		# avoid names starting with a dot
		if ($last =~ /^\./) {
			# first, remove all dots from the beginning
			$last =~ s/^\.+//g;
			$last = "FILES." . $last
		}
		# strip all dots from the end and prepend one with the extension
		$last =~ s/\.+$//g;
		$last .= '.' . $ext;
		$dirs[-1] = $last;
		$ff = File::Spec->catdir(@dirs);
	}
	if (-f $ff) {
		say "Error, file $ff already exists.";
		say "Have you already installed the files somewhere?";
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
	say $ff_fh "# $source " . ( $strip_root ? "(stripped)" : "") . " -> $root";
	say $ff_fh "VERSION 1";
	say $ff_fh "ROOTDIR " . ( $strip_root ? File::Spec->rootdir() : "$root");
	# todo: if find reports errors "can't cd to...", it is not handled
	find (\&process_file, $source);
	close $ff_fh;
	if ($changes_done or $dummy) {
		say "\nDone. Remember to backup the file $ff.";
	}
	else {
		say "\nNo changes were done. You may want to remove the file $ff.";
	}
	exit EXIT_OK;
}

# to be used with inst
sub _on_undo {
	if ($changes_done) {
		say "REMEMBER TO UNDO CHANGES MANUALLY using $0 del $ff";
		close $ff_fh;
	}
	else {
		my $ff_path = File::Spec->rel2abs($ff, $start_cwd);
		say "No changes were done. $ff is not needed and will be removed.";
		close $ff_fh;
		unless (unlink $ff_path) {
			say "Warning: can't remove file $ff_path: $!.";
		}
	}
}

sub process_file {
	my $path = $File::Find::name;
	my $file = $_; # find does chdir by default, so we'll use this variable
	# my $dir = $File::Find::dir;
	my $dst_path;
	my $save_path; # path to record in file

	return if $file eq File::Spec->curdir(); # omit 'dir' itself

	# destination: $dst_path = $root + ($path - $source)
	my @path_a = File::Spec->splitdir (
		# omit volume name (does File::Find return it?)
		( File::Spec->splitpath( $path, "dirs" ) )[1]
	);

	my @path_without_source = @path_a[@source_a .. $#path_a];
	my $path_without_source = File::Spec->catdir (@path_without_source);
	# note: keeping it simple here (catfile only), no support for VMS :)
	$dst_path = File::Spec->catfile (@root_a, @path_without_source);

	if (!$strip_root) {
		$save_path = $dst_path;
	}
	else {
		$save_path = File::Spec->catfile (
			File::Spec->rootdir(),
			@path_without_source
		);
	}

	my $src_type;
	use constant {
		tdir => 1,
		treg => 2,
		tsym => 3,
		toth => 0
	};
	# must first lstat()
	if (-l $file) {
		$src_type = tsym;
	}
	elsif (-f $file) {
		$src_type = treg;
	}
	elsif (-d _) {
		$src_type = tdir;
	}
	else {
		$src_type = toth;
	}

	if($src_type == tdir) {
		if ($dummy) {
			say $ff_fh "NEWDIR $save_path";
			return;
		}
		if(-d $dst_path) {
			# OK, dir exists, we don't touch it
		}
		elsif(-e _) {
			# skip also when $skip_on_conflict, because if src/d = dir
			# and dst/d = file, copying of src/d/something will fail anyway
			say "Error! The file $dst_path exists and it's not a directory.";
			say "\tAborting!";
			_on_undo();
			exit EXIT_ERRPROC; # with File::Find one can't abort find() it seems :/
		}
		else {
			unless($pretend) {
				unless (mkdir $dst_path) {
					say "Error! Can't create directory $dst_path - aborting!";
					say $!;
					_on_undo();
					exit EXIT_ERRPROC;
				}
				my $ret = clone_modes($file, $dst_path);
				if ($ret < 0) {
					given($ret) {
						say "Warning: can't stat $file: $!" when (-1);
						say "Warning: can't change mode for $file: $!" when (-2);
						say "Warning: can't change owner/group for $file: $!" when (-3);
					}
				}
			}
			$changes_done = 1;
			say $ff_fh "NEWDIR $save_path";
		}
	}
	elsif($src_type == treg || $src_type == tsym) {
		if ($dummy) {
			say $ff_fh "NEWFILE $save_path";
			return;
		}
		if(-d $dst_path) {
			if($skip_on_conflict) {
				say "Info: skipping file $file: destination already ",
					"exists. Destination $dst_path is a directory or a symbolic ",
					"link pointing to a directory.";
			}
			else {
				say "Error! The file $dst_path exists and IS a directory";
				say "\t(or a symbolic link pointing to a directory)";
				say "\tbut source file is not a directory. Aborting!";
				_on_undo();
				exit EXIT_ERRPROC;
			}
		}
		elsif (-e _) {
			if($skip_on_conflict) {
				say "Info: skipping file $file: destination already ",
					"exists. Destination $dst_path is a file.";
			}
			else {
				# let's yell a bit
				say "Error! The file $dst_path exists!";
				say "\tI'm not going to overwrite it. Aborting!";
				_on_undo();
				exit EXIT_ERRPROC;
			}
		}
		else {
			unless ($pretend) {
				# Do it!
				if($src_type == treg) {
					unless (copy $file, $dst_path) {
						say "Error! Can't copy file $path to $dst_path - aborting!";
						say "\t",$!;
						_on_undo();
						exit EXIT_ERRPROC;
					}
					my $ret = clone_modes($file, $dst_path);
					if ($ret < 0) {
						given($ret) {
							say "Warning: can't stat $file: $!" when (-1);
							say "Warning: can't change mode for $file: $!" when (-2);
							say "Warning: can't change owner/group for $file: $!" when (-3);
						}
					}
				}
				else { # symbolic link
					my $symlink_dest = readlink $file;
					unless (defined $symlink_dest) {
						# It's a symlink and can't read it?
						say "Error, can't read destination of symbolic link $file ",
							" - aborting!";
						say $!;
						_on_undo();
						exit EXIT_ERRPROC;
					}
					unless (symlink ($symlink_dest, $dst_path)) {
						say "Error, can't make a symbolic link $dst_path ",
							"to $symlink_dest - aborting!";
						say $!;
						_on_undo();
						exit EXIT_ERRPROC;
					}
				}
			}
			$changes_done = 1;
			say $ff_fh "NEWFILE $save_path";
		}
	}
	else {
		say "Warning, file $file is not a regular file, directory or symbolic ",
			"link and was omitted.";
	}
}

# Oh sweet!
sub clone_modes {
	my ($from, $to) = @_;
	return if(!defined $from or !defined $to);
	my ($dev, $mode, $uid, $gid) = (lstat ($from))[0,2,4,5];
	unless (defined $dev) {
		return -1;
	}
	$mode = $mode & 07777;

	unless(chmod $mode, $to) {
		return -2;
	}

	if ($change_ownership) {
		unless (chown $uid, $gid, $to) {
			return -3;
		}
	}
	return 0;
}

#################################### del #####################################

sub do_del {
	# easier to find bugs in code when using $source instead of $ff by accident:
	undef $source;
	unless ( ($ff =~ /.+\.\Q$ext\E$/) ||
		( File::Spec->case_tolerant() and $ff =~ /.+\.\Q$ext\E$/i ) )
	{
		say "The file $ff should end with .$ext.";
		exit EXIT_WRARG;
	}
	unless (open $ff_fh, "<", $ff) {
		say "Cannot open $ff for reading: $!.";
		exit EXIT_CANTCONT;
	}
	my @opers; # $opers[n] = { oper => NEW...,  path => ... }
	my $version;
	my $line = 0;
	my $rootdir; # unused, even not checked
	my $my_root = "";

	unless($root eq File::Spec->rootdir()) {
		# set root directory (all items to remove are inside it)
		$my_root = File::Spec->canonpath($root);
		say "Root directory for the operation is $my_root.";
	}

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
	close $ff_fh;

	my $path;
	@opers = reverse @opers;
	for (@opers) {
		$path = $my_root
			# assuming it "inst" and "del" will be run on the same platform
			# and that this "cating" is OK for the OS filesystem (also see
			# related comment in process_file about "keeping it simple")
			? File::Spec->catdir($my_root, $_->{path})
			: $_->{path};

		if ($_->{oper} eq 'NEWFILE') {
			unless ($pretend) {
				unless (unlink $path) {
					say "Warning: can't remove file $path.";
					say "\t$!";
				}
			}
			else {
				say "[FILE] " . $path;
				say "\tInfo: this file doesn't exist or is not a regular file."
					unless -f $path;
			}
		}
		elsif ($_->{oper} eq 'NEWDIR') {
			unless($pretend) {
				unless (rmdir $path) {
					say "Warning: can't remove directory $path.";
					say "\t$!";
					say "\tMaybe it wasn't empty because something was added";
					say "\tto it after using this tool.";
				}
			}
			else {
				say " [DIR] " . $path;
				say "\tInfo: this directory doesn't exist or the item is not a directory."
					unless -d $path;
			}
		}
	}
	say "Done! You may remove $ff if you want. Enjoy!" unless $pretend;
}

################################ parse_cmdline ###############################

sub parse_cmdline {
	my $oper = shift @ARGV;
	while (1) {
		$source = shift @ARGV;
		if(defined $source and $source eq "-p" and !$pretend) {
			$pretend = 1;
		}
		elsif(defined $source and $source eq "-dummy" and !$dummy) {
			$dummy = 1;
		}
		else {
			last;
		}
		# Check it here, too. Not necessary, but let's get the message earlier.
		if ($pretend and $dummy) {
			say "Error: -p and -dummy cannot be used together.\n";
			usage;
			exit EXIT_WRARG;
		}
	}

	given($oper) {
		when ("inst") {
			$inst = 1;
			if (!defined $source or $source eq "") {
				say "Error: you didn't provide a source dir.\n";
				usage;
				exit EXIT_WRARG;
			}
		}
		when("del") {
			$inst = 0;
			if ($dummy) {
				say "Error, -dummy can only be used with \"inst\".";
				exit EXIT_WRARG;
			}
			if (!defined $source or $source eq "") {
				say "Error: you didn't provide a .$ext file.\n";
				usage;
				exit EXIT_WRARG;
			}
			$ff = $source;
		}
		when(["-h", "--help"]) {
			help;
			exit EXIT_OK;
		}

		say "Error: incorrect args.\n";
		usage;
		exit EXIT_WRARG;
	}

	say "Warning, source directory is $source and begins with a `-' - make sure\n",
		"it's not due to a mistake in parameters.\n"
		if ($source =~ /^-/);

	while(my $arg = shift @ARGV) {
		given ($arg) {
			when("-p") {
				$pretend = 1;
			}
			when("-dummy") {
				unless ($inst) {
					say "Error, -dummy can only be used with \"inst\".";
					exit EXIT_WRARG;
				}
				$dummy = 1;
			}
			when("-r") {
				say "Warning, -r DIR specified once again, overriding." if defined $root;
				$root = shift @ARGV;
				if (!defined $root or $root eq "") {
					say "You should provide root (destination) directory name after -r.";
					exit EXIT_WRARG;
				}
			}
			when("-file") {
				if(!$inst or defined $ff) {
					say "Warning, source file overridden by -file option."
				}
				$ff = shift @ARGV;
				if (!defined $ff or $ff eq "") {
					say "You should provide a .$ext file name after -file.";
					exit EXIT_WRARG;
				}
			}
			when(["-h", "--help"]) {
				help;
				exit EXIT_OK;
			}
			when ("-nco") {
				unless ($inst) {
					say "Error, -nco can only be used with \"inst\".";
					exit EXIT_WRARG;
				}
				$change_ownership = 0;
			}
			when ("-sc") {
				unless ($inst) {
					say "Error, -sc can only be used with \"inst\".";
					exit EXIT_WRARG;
				}
				$skip_on_conflict = 1;
			}
			when ("-strip") {
				unless ($inst) {
					say "Error, -strip can only be used with \"inst\".";
					exit EXIT_WRARG;
				}
				$strip_root = 1;
			}
			say "Error: too much or wrong parameters ($arg).\n";
			usage;
			exit EXIT_WRARG;
		}
	}
	if ($pretend and $dummy) {
		say "Error: -p and -dummy cannot be used together.\n";
		usage;
		exit EXIT_WRARG;
	}
	$root = $root // File::Spec->rootdir();
}
