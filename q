#!/usr/bin/perl

my $pl="/tmp/q.playlist-future";
my $plh="/tmp/q.playlist-history";
my $responsef = "/tmp/q.response";
my $read_pipe = "/tmp/q.cmds-to-p";
my $q_player = "/usr/local/bin/q.player";
my $mx_log = "/tmp/q.mx-log";
my $mx_err = "/tmp/q.mx-err";
my $q_pl_prefix = "/tmp/q.saved-playlist-"; #Cannot have any shell-interperatable chars.


my $isrun = "/usr/local/bin/isrunning";

my $debug = undef;
#my $debug = "yes";

use Fcntl qw(:DEFAULT :flock);
use Term::ReadKey; # For screen width
use File::Find;


# This is checked first off, everytime to use the internal pager.
if ( ($#ARGV == 0) && ($ARGV[0] =~ /^--non-paging-help$/) ) {
print <<EOF;
	
   q -- queue cuts for (and send cmds to) a background audio player on Dr Gonzo.


Usage:        q  [ NUMBER ]  [ COMMAND ]  [ FILE_1 [FILE_2] [FILE_3] ... ]

    Where NUMBER, if given, is a decimal natural number (like 1, 2, 3, etc.)
COMMAND, if given, is a command to do something other than queue files to play;
and FILE(S) is a list of files to queue.


    FILE(S) is a list of files -- either given with a path (absolute or relative to the current directory) or are in the current directory.  If the given file is a directory, then all regular files within it are queued (unless that directory contains a VIDEO_TS sub-directory, indicating that it is a DVD, in which case all titles (not files) are queued).  If no NUMBER is given then FILE(S) are added to the end of the queue.  If NUMBER is given on the command line then FILE(S) are placed in the queue at NUMBER, with a special case:
        If NUMBER is "0" then the currently playing cut is immediately stopped  or skipped and the first FILE is played, with the rest of the FILE(S) following.
        If NUMBER is "1" then FILE(S) are played after the current one is done.
		And so on.

	
===  General Commands:

    If no COMMAND is given then the command "queue" is assumed.  All COMMANDS can be preceeded with a "-" (hyphen) or a "--" (dash) with no effect.  Also the first character is usually case in-sensitive.

    "--", "q", or "Queue" -- The queue command, everything after this on the command line is assumed to be a FILE, useful if you have files to play that look like a COMMAND or a NUMBER.  See the description above.

    "?", "h", "Help", or no arguments at all -- Display this help screen.

    "p" or "Pause" -- Pause or play (unpause) the currently playing cut. (Also see External Commands.)

	"]" -- Seek forward 10 sec., or if NUMBER is given seek 10 * NUMBER sec.

	"[", "[]", or "][" -- Seek backwards 10 sec., or 10 * NUMBER sec. if NUMBER is given.

    "s", "Skip", or "Stop" -- Skip/stop the current cut and play the next one; or skip the next NUMBER cuts (this could take a little while, so if you want to skip a lot of cuts consider the ClearList command with a NUMBER argument).

    "-", "_", "-v", "_v", "-Vol", "_vol", "-volume", or "_Volume"
        -- Decrese volume by 3 ticks, or NUMBER ticks if given. (Also see External Commands.)

    "=", "+", "+v", "=v", "+Vol", "=vol", "+volume", or "=Volume"
        -- Increse volume by 3 ticks, or NUMBER ticks if given. (Also see External Commands.)

    "m" or "Mute" -- Mute the currently playing cut.

    "c", "cmd", or "Command" -- Cmd mode: Send keystrokes directly to mx.

    "i" or "Info" -- Print some information about the currently playing (or last played) cut.  If a NUMBER argument is given then info about the NUMBER most recent cut is displayed.

    "f" or "Find" -- Find files with names containing the following arguments located in /media/music.  All the arguments are catenated, separated by spaces, and treated as one search term; the argument is a regex.

    "k" or "Kill" -- Try to kill process called q.player, then clear the future & history playlists, and remove the command-pipe, logs, and response file.  This will not work if a NUMBER is provided (a file called kill will be queued).
         Try this if q isn't working right.

    "r", "Replay", "Requeue" -- Replay (or requeue) the most recently started track.  Not providing a NUMBER argument is the same as providing "0" or "1".  Higher number requeue tranck further in the history.


===  Playlist Commands:

	There are two playlists always in use, the future playlist, and the history playlist, and there can be optional saved playlists.  The future playlist holds the list of files that are queued to be played.  As soon as a cut starts playing it is removed from the top of the future playlist and appeneded to the bottom of the history playlist; the currently playing cut is therefore that last entry in the history playlist.

    "l", "pl", "list", or "playlist" -- list the next NUMBER cuts in the queue, if NUMBER is not given then the next 20 cuts are listed.

    "lh", "plh", "PlaylistHist" -- list the last NUMBER cuts in the history, if no NUMBER is given then the next 20 cuts are listed.
	
    "shuf", "rand", "Shuffle", "random", or "Randomize" -- Shuffle the cuts in the future playlist.

    "cl", or "ClearList" -- Clear the future playlist, or if NUMBER is given, clear the next NUMBER cuts.
	
    "ch", "ClearHist", or "clearhistory" -- Clear the playlist history, or if NUMBER is given, clear the last NUMBER cuts.

    "pld", "PlaylistDisp" -- Display a list of saved playlists.

    "pls", "PlayListSave" -- Save the current history and future playlists as one playlist.  You can queue up a bunch of cuts and then save everything with a name that can be loaded later; before doing that it may be a good idea to run ClearHist and ClearList so anything left over won't included in the saved paylist.  All arguments following this command are used in the name.

    "pll", "PlayListLoad" -- The following arguments are taken to be the name of a playlist to load and start playing.  This does not overwrite anything already queued.  You clear the exsisting one first with ClearHist and ClearList, or you can supply a NUMBER argument of 0 to start playing the loaded list immediately.

    "plr", "PlayListRemove" -- Removes (or deletes) the named saved playlist.



About:
	This program is mantained by Saneesh.  Please tell me if you think of anything that is inconvenient, or could be fixed.

	bye.


EOF
exit;
}

sub usage () {
	exec("$0 --non-paging-help | less");
	exit; # Not needed.
}

# Before we do any error checking, we need to check the response file.
if(-r $responsef) {
	print ""
	. "\n===============================================================\n"
	. "     There is a response file from the last run.\n"
	. "                                     Which says:"
	. "\n===============================================================\n";
	system("cat $responsef >&2");
	print "\n===============================================================\n"
		. "     That is now going to be deleted.  To try and do whatever\n"
		. "         you just tried to, hit the up-arrow and re-run q."
	. "\n===============================================================\n\n";
	unlink($responsef);
	exit 1;
}

# Remember this is inverted return values.
if( system("$isrun is-non-real-rand-name-234762934234 >&/dev/null") ) {
	die "Program $isrun not found.\n";
}

# We also call this is the re-start func.
sub start_q_player {
	system("touch $pl $plh $mx_log $mx_err");
	chmod(0666, ($pl, $plh, $mx_log, $mx_err));
	# Then make sure the command pipe is ther.
	if( ( not -p $read_pipe ) || ( not -w $read_pipe ) ) {
			# Remember the return form system is inverted.
		unlink($read_pipe);
		if ( system("mkfifo -m 777 $read_pipe") ) {
			die "Error creating _writable_ fifo \"$read_pipe\".";
		}
	}
	( -w $pl ) || die "Cannot write to $pl";
	( -w $plh ) || die "Cannot write to $plh";
	( -w $mx_log ) || die "Cannot write to $mx_log";
	( -w $mx_err ) || die "Cannot write to $mx_err";
	if ( -r $responsef ) {
		chmod 0666, $responsef;
		( -w $responsef ) || die "Cannot write to $responsef";
	}

	if( 0 == system("$isrun q.player >&/dev/null") ) {
		if( system("$q_player &") ) {
			die "Could not start \"$q_player\".\n";
		}
		setpgrp `$isrun -c $q_player`, 100;
	}
}

sub send_mx {
	# We always send this.
	system("echo -ne \"@_\" >> $read_pipe &");

	if("@_" =~ /[\x00-\x1f\x80-\xff]/) {
		if(3 == length "@_") {
			print "Sent \\[" . substr("@_", 2, 1) . " to mx.                                      \n";
		} else {
			print "Sent ??? to mx.                                      \n";
		}
	} else {
		print "Sent \"@_\" to mx.                                      \n";
	}
	return 1;  # Good.
}

# this will try and kill all q.player's
# Also it should delet all relevent files.
sub func_kill {
	my $tmp_pid;
	send_mx("\\r"); # Incase one is still playing.
	select(undef, undef, undef, 0.5); # Silly perl sleep substitute.
	system("killall q.player");
	select(undef, undef, undef, 0.1); # Silly perl sleep substitute.
	system("killall -9 q.player");
	$tmp_pid = `$isrun -c $q_player`;
	chomp $tmp_pid;
	if($tmp_pid != 0) {
		print "Could not kill proc $tmp_pid ($q_player).\n";
	}


	$tmp_pid = `$isrun -c $read_pipe`;
	#system("/usr/bin/pkill -P $tmp_pid"); # kill proc with this parent pid.
	select(undef, undef, undef, 0.1); # Silly perl sleep substitute.
	system("/usr/bin/kill $tmp_pid");
	$tmp_pid = `$isrun -c $read_pipe`;
	chomp $tmp_pid;
	if($tmp_pid != 0) {
		print "Could not kill proc $tmp_pid.\n";
	}

	
	send_mx("\\r"); # This will background.
	system("cat $read_pipe >&/dev/null &");

	select(undef, undef, undef, 0.1); # Silly perl sleep substitute.

	# Kill everythig again.
	$tmp_pid = `$isrun -c $read_pipe`;
	#system("/usr/bin/pkill -P $tmp_pid"); # kill proc with this parent pid.
	select(undef, undef, undef, 0.1); # Silly perl sleep substitute.
	system("/usr/bin/kill $tmp_pid");
	$tmp_pid = `$isrun -c $read_pipe`;
	chomp $tmp_pid;
	if($tmp_pid != 0) {
		print "Could not kill proc $tmp_pid.\n";
	}


	# rm everything, except saved playlists.
	system("rm", "-f", $pl, $plh, $responsef, $read_pipe, $mx_log, $mx_err);
}

# This is the func to shuffle a list.
# fisher_yates_shuffle( \@array ) : 
# generate a random permutation of @array in place
sub fisher_yates_shuffle {
	my $array = shift;
	my $i;
	for ($i = @$array; --$i; ) {
		my $j = int rand ($i+1);
		next if $i == $j;
		@$array[$i,$j] = @$array[$j,$i];
	}
}

# This is a function to print a cardinal number.
sub print_card {
	my $tmp;
	if ( ( $_[0] ) and ( $_[0] =~ /^[0-9]+$/ ) ) {
		$tmp = $_[0];
		print "$tmp";
		if (substr($tmp, -2, 1) eq "1") { print "th";
		} elsif(substr($tmp, -1, 1) eq "1") { print "st";
		} elsif(substr($tmp, -1, 1) eq "2") { print "nd";
		} elsif(substr($tmp, -1, 1) eq "3") { print "rd";
		} else { print "th"; }
	} else {
		print "unknown";
	}
}

# This is the list to add at $num.
my @pl_add = ();
my $tmp;  # Just a useful dummy variable.
my @f = (); # List to read in files.


# If we are killing, then we don't need to do anything else.
if($#ARGV >= 0) {
	if ($ARGV[0] =~ /^[-]?[-]?[kK](ill)?$/) {
		if(defined $ARGV[1]) {
			print "Garbage after kill command on command-line.\n";
		} else {
			print "Cmd: Kill, try and remove all running parts of this program.\n";
			func_kill;
		}
		exit 0;
	}
}

start_q_player;

# Now let's start checking arguments.
if( ($#ARGV == -1) # We have no arguments
	|| ($ARGV[0] =~ /^[-]?[-]?[hH?](elp)?$/) ) { # or help was asked for.
		usage;
}

# This is so we can keep popping then off the arg line.
my @args = @ARGV;  # So we have _some_ arguments.
my $arg;  # For each one at a time.
my $done = undef;
my $num = undef;  # This is the default count valuee.
# First we just process the commands.
while( (@args) and (not $done) ) {
	$arg = shift(@args);
				# Get number.
	if($arg =~ /^[-]?[-]?[0-9]+$/ ) {
		if($num) {
			print "Error: multiple number arguments found.\n(If you have files to queue that are numbers, use the \"--\" command.)\n";
			exit 1;
		}
		$num = $arg;
				# Pause
	} elsif($arg =~ /^[-]?[-]?[pP](ause)?$/ ) {
		print "Cmd: Pause or play (unpause).\n";
		if ( $num ) { print "This command cannot take a NUMBER argument, exiting.\n"; exit 1; }
		send_mx(" ");
				# Stop/Skip
	} elsif($arg =~ /^[-]?[-]?[sS]((top)|(kip))?$/ ) {
		if ( ( $num ) and ( $num > 1 ) ) {
			print "Cmd: Skip the next $num cuts.\n";
			while($num) {
				send_mx("\\r");
				$num--;
				select(undef, undef, undef, 1); # Silly perl sleep substitute.
			}
		} else {
			print "Cmd: Skip the current cut.\n";
			send_mx("\\r");
		}
		$num = undef;
				# Seek forward num*10 sec
	} elsif($arg =~ /^[-]?[-]?\]$/ ) {
		if ( ( $num ) and ( $num > 1 ) ) {
			print "Cmd: Seek forward $num * 10 sec.\n";
			while($num) {
				send_mx("\033[C");
				$num--;
				select(undef, undef, undef, 0.1); # Silly perl sleep substitute.
			}
		} else {
			print "Cmd: Seek forward 10 sec.\n";
			send_mx("\033[C");
		}
		$num = undef;
				# Seek backwards num*10 sec
	} elsif($arg =~ /^[-]?[-]?((\[(\])?)|(\]\[))$/ ) {
		if ( ( $num ) and ( $num > 1 ) ) {
			print "Cmd: Seek backwards $num * 10 sec.\n";
			while($num) {
				send_mx("\033[D");
				$num--;
				select(undef, undef, undef, 0.1); # Silly perl sleep substitute.
			}
		} else {
			print "Cmd: Seek backwards 10 sec.\n";
			send_mx("\033[D");
		}
		$num = undef;
				# Mute/Unmute
	} elsif($arg =~ /^[-]?[-]?[mM](ute)?$/ ) {
		print "Cmd: Mute.\n";
		if ( $num ) { print "This command cannot take a NUMBER argument, exiting.\n"; exit 1; }
		send_mx("m");
				# This is the decrese volume thing.
	} elsif($arg =~ /^[-_]([vV](ol(ume)?)?)?$/ ) {
		if( (defined $num) && ( $num > 0 ) ) { $tmp = $num; } else { $tmp = 3; }
		print "Cmd: Lower volume by $tmp ticks.\n";
		while( $tmp ) {
			send_mx("9");
			$tmp--;
		}
		$num = undef;
				# This is the increse volume thing.
	} elsif($arg =~ /^[+=]([vV](ol(ume)?)?)?$/ ) {
		if( (defined $num) && ( $num > 0 ) ) { $tmp = $num; } else { $tmp = 3; }
		print "Cmd: Raise volume by $tmp ticks.\n";
		while( $tmp ) {
			send_mx("0");
			$tmp--;
		}
		$num = undef;
				# Command mode, send key-strokes diectly to mx
	} elsif($arg =~ /^[-]?[-]?[cC]((md)|(ommand))?$/ ) {
		print "Cmd: Goto Command mode.\n";
		$arg = shift(@args);
		if($arg) {
			# We have extra stuff, so we recurse.
			if ( $num ) {
				system("$0", $num, "--", $arg, @args)
			} else {
				system("$0", "--", $arg, @args)
			}
		} else {
			if ( $num ) { die "This command (cmd-mode) cannot take a NUMBER argument, exiting.\n"; }
		}
		use Term::ReadKey;
		ReadMode 'cbreak';
		print "Every key-stroke will be passed to mx (Ctrl-C to exit).\n\n\t\tCtrl-C to exit.\n\n";
		if (!defined($num = fork())) {
			# fork returned undef, so failed
			die "Failed on fork: $!";
		} elsif ($num == 0) {
			# Fork returned 0, so this branch is the child.
			select(undef, undef, undef, 0.3); # Silly perl sleep substitute.
			exec "tail --follow=name \"$mx_log\" \"$mx_err\" -c 2000 --pid=$$ --sleep-interval=0.4"; # If the exec fails, fall through to the next statement.
			die "Can't exec tail -f: $!";
		}
		$arg = 1;
		while($arg == 1) {
			$tmp = ReadKey(0);
			if(ord("$tmp") == 27) {
				$tmp = ReadKey(0.25);
				if($tmp eq undef) {
					next;  # Ignor this escape.
				} else {
					$tmp = ReadKey(0.25);
					if($tmp eq undef) {
						next;
					} else {
						$arg = send_mx("\033[$tmp");
					}
				}
			} else {
				$arg = send_mx($tmp);
			}
		}
		# We should never get here.
		system("kill $num");
		select(undef, undef, undef, 0.5); # Silly perl sleep substitute.
		system("kill -9 $num");
		ReadMode 'normal';
		die "Somehow returned from commabd mode, exiting.";
				# Clear the playlist.
	} elsif($arg =~ /^[-]?[-]?[cC][lL](earlist)?$/ ) {
		if ( ( $num ) and ( $num > 0 ) ) {
			print "Cmd: Clear the next $num cuts in the future playlist.\n";
		} else {
			$num = undef;
			print "Cmd: Clear the future playlist.\n";
		}
		sysopen(F, $pl, O_RDWR | O_CREAT) || die "Could not open $pl\n";
		flock(F, LOCK_EX) || die "Could not get flock on $pl\n";
		@f = ();
		if( $num ) {
			for $arg (1 .. $num) {
				$tmp = <F>;
			}
			@f = <F>;
		}
		truncate(F, 0); seek(F, 0, 0);
		if($#f >= 0) {
			print F @f;
		}
		close(F); #This removes the flock.
		$num = undef;
				# Clear the playlist history.
	} elsif($arg =~ /^[-]?[-]?[cC](lear)?[hH](ist)?$/ ) {
		if ( ( $num ) and ( $num > 0 ) ) {
			print "Cmd: Clear the last $num cuts in the history.\n";
		} else {
			print "Cmd: Clear the history playlist.\n";
			$num = undef;
		}
		sysopen(F, $plh, O_RDWR | O_CREAT) || die "Could not open $plh\n";
		flock(F, LOCK_EX) || die "Could not get flock on $plh\n";
		@f = ();
		if( $num ) {
			@f = <F>;
			if($#f <= $num - 1) {
				@f = ();
			} else {
				# Num is smaller than $#f
				$tmp = $#f - $num;
				@f = @f[0 .. $tmp];
			}
		}
		# Now that we've slurped the cuts remaining, truncate it.
		truncate(F, 0); seek(F, 0, 0);
		if($#f >= 0) {
			print F @f;
		}
		close(F); #This removes the flock.
		$num = undef;
				# Print the last NUMBER | 20 cuts in the history.
	} elsif($arg =~ /^[-]?[-]?([pP](lay)?)?[lL](ist)?[hH](ist)?$/ ) {
		my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
		if ( $wchar < 8 ) { $wchar = 80; }
		if ( $num ) { $hchar = $num; } else { $hchar = 20; }
		print "     The last $hchar things in the history are:\n";
		open(F, "<" . $plh) or die "Could not open \"$plh\" for reading.\n";
		@f = <F>;
		for $arg(1 .. $hchar) {
			$tmp = $f[0 - $arg];
			if($tmp) {
				chomp $tmp;
				if(length $tmp > $wchar) {
					print "..." . substr($tmp, -1 * $wchar + 3) . "\n";
				} else {
					print $tmp . "\n";
				}
			}
		}
		close(F); #This removes the flock.
		$num = undef;
				# Requeue the NUMBER | 1st cut in the history.
	} elsif($arg =~ /^[-]?[-]?[rR](e)?((queue)|(play))?$/ ) {
		if ( $num ) { if($num == 0) { $num = 1; } } else { $num = 1; }
		if ( $num < 1 ) { die "The NUMBER argument ($num) is invalid."; }
		print "Cmd: Requeue the "; print_card($num); print " cut(s) in the history playlist.\n";
		open(F, "<" . $plh) or die "Could not open \"$plh\" for reading.\n";
		@f = <F>;
		$arg = $f[-$num];
		chomp $arg;
		close(F); #This removes the flock.
		if($arg) {
			system("$0", "--", $arg);
		} else {
			die "The NUMBER argument is out of range.";
		}
		$num = undef;
				# Suffle the playlist.
	} elsif($arg =~ /^[-]?[-]?(([sS]huf(fle)?)|([rR]and(om(ize)?)?))$/ ) {
		print "Cmd: Shuffle the future playlist.\n";
		if ( $num ) { die "This command cannot take a NUMBER argument, exiting.\n"; }
		sysopen(F, $pl, O_RDWR | O_CREAT) || die "Could not open $pl\n";
		flock(F, LOCK_EX) || die "Could not get flock on $pl\n";
		@f = (); @f = <F>;
		truncate(F, 0); seek(F, 0, 0); # Now we truncate it.
		if($#f > 0) { # The $#f returns one less than the # of elems, but we don't have to sort 1 elem.
			fisher_yates_shuffle( \@f );    # permutes @array in place
		}
		print F @f;  # Wrie it back to $pl.
		close(F); # This releases the flock.
				# Find a file in "/media"
	} elsif($arg =~ /^[-]?[-]?[fF](ind)?$/ ) {
		print "Cmd: Find.  Hit 'q' to quit, 'space' for next page.  Finding...\n";
		if ( $num ) { die "This command cannot take a NUMBER argument, exiting.\n"; }
		exec("find /media/music/ -iregex '.*" . join(" ", @args) . ".*' | less");
		exit;  # You know we won't get this far right?
				# This is to display the next NUMBER | 20 cuts in a playlist.
	} elsif($arg =~ /^[-]?[-]?([pP](lay)?)?[lL](ist)?$/ ) {
		print "Cmd: Print the playlist.\n";
		my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
		if ( $wchar < 8 ) { $wchar = 80; }
		if ( $num ) { $hchar = $num; } else { $hchar = 20; }
		$tmp = `wc -l < "$pl"`; chomp $tmp;
		print "     The next $hchar (of $tmp) things in the playlist are:\n";
		open(P, "<" . $pl) or die "Could not open \"$pl\" for reading.\n";
		for $arg(1 .. $hchar) {
			$tmp = <P>;
			if($tmp) {
				chomp $tmp;
				if(length $tmp > $wchar) {
					print "..." . substr($tmp, -1 * $wchar + 3) . "\n";
				} else {
					print $tmp . "\n";
				}
			}
		}
		close(P);
		$num = undef;
				# This is to display the saved playlists.
	} elsif($arg =~ /^[-]?[-]?[pP](lay)?[lL](ist)?[dD](isp(lay)?)?$/ ) {
		print "Cmd: Display all the saved playlists.\n";
		if ( $num ) { die "This command cannot take a NUMBER argument, exiting.\n"; }
		@f = `ls $q_pl_prefix* 2>/dev/null`;
		if(@f) {
			print "The saved playlists are:\n";
			for $arg(@f) {
				print substr($arg, length $q_pl_prefix);
			}
		} else {
			print "There do not appear to be any saved playlists.\n";
		}
				# This is to remove a saved playlist.
	} elsif($arg =~ /^[-]?[-]?[pP](lay)?[lL](ist)?[rR](emove)?$/ ) {
		print "Cmd: Remove a saved playlist.\n";
		if ( $num ) { die "This command cannot take a NUMBER argument, exiting.\n"; }
		if( unlink($q_pl_prefix . join(" ", @args)) ) {
			print "Playlist removed.\n";
			exit 0;
		} else {
			die "Unable to remove the specified paylist.  Maybe the name is not escaped properly\n";
		}
				# This is to load a saved playlist.
	} elsif($arg =~ /^[-]?[-]?[pP](lay)?[lL](ist)?[lL](oad)?$/ ) {
		print "Cmd: Load a saved playlist.\n";
		if(-r $q_pl_prefix . join(" ", @args)) {
			open(F, "<" . $q_pl_prefix . join(" ", @args)) or die "Could not open the playlist (" . $q_pl_prefix . join(" ", @args) . ")for reading.\n";
			@args = (); # Remove the name from the list to load.
			while(<F>) {
				chomp;
				unshift @args, $_;
			}
			close(F);
		} else {
			die "Cannot seem to find that playlist.  Maybe the name is not escaped well?\n";
		}
				# This is to save a saved playlist.
	} elsif($arg =~ /^[-]?[-]?[pP](lay)?[lL](ist)?[sS](ave)?$/ ) {
		print "Cmd: Save a saved playlist.\n";
		if(@args) {
			$arg = $q_pl_prefix . join(" ", @args);
		} else {
			die "No playlist name provided, exiting.\n";
		}
		if(-e $arg) {
			die "That playlist already exsists, not saving.";
		} else {
			if( ($plh =~ /"/) or ($pl =~ /"/) or ($arg =~ /"/) ) {
				die "One of the filenames has a \" in it, can't process, exiting.\n";
			} elsif(system("cat \"$plh\" \"$pl\" > \"$arg\"")) {
				die "There was an unknown error, sorry.\n";
			} else {
				chmod(0666, $arg);
				die "Done, I think.\n";
			}
		}
				# Info about the currently playing or last played cut.
	} elsif($arg =~ /^[-]?[-]?[iI](nfo)?$/ ) {
		if ( ( $num ) and ( $num > 1 ) ) {
			print "Cmd: Get info on the "; print_card($num); print " most recent cut.\n";
		} else {
			print "Cmd: Get info on current (or last) cut.\n";
			$num = 1;
		}
		open(F, "<" . $plh) || die "Could not open/read " . $plh . ": $!";
		flock(F, LOCK_EX) || die "Could not get lock on " . $plh . ": $!";
		@f = ();
		@f = <F>;
		close(F); # This removes the flock.
		if($num > 1 + $#f) {
			print "There is no "; print_card($num); print " most recent cut, exiting.\n";
			exit 1;
		}
		chomp $f[0 - $num];
		$tmp = "\"" . $f[0 - $num] . "\"";
		$tmp = `mp3info -x $tmp 2>/dev/null`;
		if(length $tmp > 0) {
			print "\n$tmp";
		} else {
			$tmp = "\"" . $f[0 - $num] . "\"";
			$tmp = `ogginfo $tmp 2>/dev/null`;
			if(length $tmp > 0) {
				print "\n$tmp";
			} else {
				print "Couldn't get info on the file : " . $f[0 - $num] . "\n";
			}
		}
		$num = undef;
			# This is the no more commands conditions.
	} elsif($arg =~ /^[-]?[-]?[qQ](ueue)?$/) {
		$done = "yes";
			# This is the no more commands conditions.
	} elsif($arg =~ /^[-][-]$/) {
		$done = "yes";
	} else {  # Assume the rest are files.
		$done = "yes";
		unshift(@args, $arg);  #Put the last one back in the array.
	}
	if($debug) { print "Processed command \"$arg\".\n"; }
}

sub wanted {
	my $found = $File::Find::name;
	if( -f $found ) {
		$found =~ s/"/\\"/;
		push @pl_add, $found . "\n";
	}
}
# Now we just have files left, maybee.
while(@args) {
	$arg = shift(@args);
	if( -r "$ENV{'PWD'}/$arg" ) {
		$arg = "$ENV{'PWD'}/$arg";
	}
	if( -d $arg ) {
		if( (-d "$arg/video_ts") or (-d "$arg/VIDEO_TS") ){
			print "Found a VIDEO_TS dir, queuing this as a DVD: $arg\n";
			$arg =~ s/"/\\"/;  # Escape anr '"' chars.
			push @pl_add, "$arg\n";
		} else {
			find(\&wanted, ($arg));
		}
	} else {
		if( ! -r "$arg") {
			print "Can not find file, but queuing it anyway: $arg\n";
		}
		$arg =~ s/"/\\"/g;  # Escape anr '"' chars.
		push @pl_add, "$arg\n";
	}
}

# Now we actually queue everything to the playlist.
# Try to read in the playlist.
sysopen(F, $pl, O_RDWR | O_CREAT) || die "Could not open $pl\n";
flock(F, LOCK_EX) || die "Could not get flock on $pl\n";
@f = ();
@f = <F>;
# Now we truncate it.
truncate(F, 0);
seek(F, 0, 0);

if(defined $num) {
	$tmp = 1;
	while( ($tmp < $num) && ($tmp-1 <= $#f) ) {
		print F $f[$tmp-1];
		$tmp++;
	}
	print F @pl_add;
	if($tmp-1 <= $#f) {
		print F @f[$tmp-1 .. $#f];
	}
	# Do this while the file is open incase q.player is waiting on the flock.
	if ( $num == 0 ) { send_mx "\\r"; }
} else {
	print F @f;
	print F @pl_add;
}

close F; # This looses the flock.

# Now we print what we've done.
if($#pl_add >= 0) {
	print "Added ";
	if($#pl_add >= 1) {
		print $#pl_add+1 . " cuts";
	} else {
		print "a cut";
	}
	print " to the ";
	if(defined $num) { 
		if($num == 0) {
			print "very beginning of";
		} else {
			print_card($num);
			print " position in";
		}
	} else {
		print "end of";
	}
	print " the queue. (If there's no sound, maybe it's paused?)\n";
}

if($debug) { print "Done.\n"; }
