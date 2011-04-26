#!/usr/bin/env perl

# you probably need dev-perl/JSON-XS, dev-perl/URI,
# and dev-perl/libwww-perl to use this

# a simple interface to packages.sabayon.org
# (C) 2011 by Enlik <poczta-sn at gazeta . pl>
# license: MIT

use warnings;
use strict;
use 5.010;
use Term::ANSIColor;
use LWP::UserAgent;
use URI::Escape;
use JSON::XS;

# options (mostly API options):
# $o_var = ( option => { API => 'API key', desc => 'description' } )
# note: those "API keys" can mean different API-related things (for example lib->{API})
# arrays to preserve order as specified, hashes are below
my @h_arch = (	amd64 => { API => 'amd64', desc => 'amd64' },
				x86 => { API => 'x86', desc => 'x86' } );
				# "arch" if Portage selected: hard-coded in make_URI
my @h_type = (	pkg => { API => 'pkg', desc => 'package search' },
				desc => { API => 'desc', desc => 'description' },
				path => { API => '', desc => 'path' },
				lib => { API => 'sop:', desc => 'package that provides a library (.so)' },
				match => { API => 'match', desc => 'package matching' } );
my @h_order = ( alph => { API => 'alphabet', desc => 'alphabetically' },
				vote => { API => 'vote', desc => 'by votes' },
				downloads => { API => 'downloads', desc => 'by downloads' },
				size => { API => 'alphabet', desc => 'by size' } );
my @h_repo = (	sl => { API => 'sabayonlinux.org', desc => 'sabayonlinux.org (Sabayon repository)' },
				limbo => { API => 'sabayon-limbo', desc => 'sabayon-limbo (Sabayon testing repository)' },
				p => { API => 'portage', desc => 'Portage (with Sabayon overlay)', source => 1 },
				psl => { API => 'portage', desc => 'Sabayon overlay', source => 1 },
				pg => { API => 'portage', desc => 'Portage' , source => 1 } );
				# since number of results is limited, I think "all" is useless (and see "note" below)
				#all => { API => undef, desc => 'sabayonlinux.org, Limbo and Portage' } );

my %h_arch = @h_arch;
my %h_type = @h_type;
my %h_order = @h_order;
my %h_repo = @h_repo;

# default values
my $s_arch = 'amd64';
my $s_type = 'pkg';
my $s_order = 'alph';
my $s_repo = 'sl';

# another values
my $branch = "5"; # not used on Portage search
my $use_colour = 1;
my $quiet_mode = 0;

# set options and the search $key
my $key;
if(@ARGV) {
	parse_cmdline(@ARGV);
}
else {
	interactive_ui();
}
my $data = get_data(make_URI($key));
parse_and_print ($data);
exit 0;

######## make_URI ########

sub make_URI {
	my $key = shift or die "no arg!";
	my $key_ok = uri_escape $key;
	my $URI = "http://packages.sabayon.org/search?q=";
	if ($s_type eq "lib" or $s_type eq "path") {
		$URI .= $h_type{$s_type}->{API} . $key_ok;
	}
	else {
		$URI .= $key_ok;
		$URI .= "&t=" . $h_type{$s_type}->{API};
	}

	unless ($s_repo eq "all") {
		if ($h_repo{$s_repo}->{source}) {
			$URI .= "&a=arch";
		}
		else {
			$URI .= "&a=" . $h_arch{$s_arch}->{API};
			$URI .= "&b=$branch";
		}
	}
	($URI .= "&o=" . $h_order{$s_order}->{API}) unless $s_order eq "size";
	$URI .= "&render=json";
	$URI;
}

######## get_data ########

sub get_data {
	my $URI = shift or return;
	my $str;
	my $_file = 'bla'; # local file with data, set for *debugging* purposes
	undef $_file;
	if (defined $_file) {
		say str_col("green", ">>  "), str_col("red", "@@ "),
			str_col("green", "Reading data from file...");
		$str = `cat "$_file"`;
	}
	else {
		my $ua = LWP::UserAgent->new;
		$ua->timeout(15);
		$ua->env_proxy;

		unless ($quiet_mode) {
			say str_col("green", ">>  "), str_col("red", "@@ "),
				str_col("green", "Please wait, downloading data...");
		}
		my $resp = $ua->get($URI);
		unless($resp->is_success) {
			say STDERR "Error fetching data: " . $resp->status_line;
			exit 1;
		}

		$str = $resp->content;
	}
	$str;
}

######## parse_and_print ########

sub _pnt_pkg {
	my $atom = shift;
	say str_col("green",">>      "), str_col("bold red","@@ Package: "),
			str_col("bold",$atom);
}

sub _pnt_spm_atom {
	my $atom = shift;
	my $spm_repo = shift;
	my %opts = @_; # quiet, foreign
	my $str = "";
	# example for quiet=0, foreign=1:
	# >>      (@@ Package: dev-dotnet/gudev-sharp-0.1::gentoo)
	if ($opts{quiet}) {
		$str .= "(" if $opts{foreign};
		$str .= $atom;
		$str .= $opts{foreign} ? str_col("bold red", "::") : str_col("bold green", "::");
		$str .= str_col("blue",$spm_repo);
		#$str .= str_col("bold blue", "::");
		#$str .= $opts{foreign} ? str_col("red", $spm_repo) : str_col("green", $spm_repo);
		$str .= ")" if $opts{foreign};
	}
	else {
		$str .= str_col("green",">>      ");
		$str .= "(" if $opts{foreign};
		$str .= str_col("red","@@ Package: ");
		$str .= $opts{foreign} ? $atom : str_col("bold",$atom);
		$str .= $opts{foreign} ? str_col("bold red", "::") : str_col("bold green", "::");
		$str .= str_col("blue",$spm_repo);
		#$str .= str_col("bold blue", "::");
		#$str .= $opts{foreign} ? str_col("red", $spm_repo) : str_col("green", $spm_repo);
		$str .= ")" if $opts{foreign};
	}
	say $str;
}

sub _pnt_prop {
	my $desc = shift;
	my $color = shift;
	my $prop = shift;
	my $len = length $desc;
	my $pad = $len > 20 ? 20 : 20 - $len;
	say str_col("green",">>")," "x9, str_col("green",$desc),
			" "x$pad, str_col($color,$prop);
}

sub _pnt_prop_wrap {
	my $desc = shift;
	my $color = shift;
	my $prop = shift;
	my $len = length $desc;
	my $WIDTH = 80;
	my $pad = $len > 20 ? 20 : 20 - $len;

	my $textlen = length $prop;
	# $indent = space on the beginning of a line
	my $indent = 2 + $len + 9 + $pad;
	#my $indenttext =  " " x $indent;
	my $indenttext = str_col("green", ">>") . " " x ($indent - 2);
	my $widthavail = $WIDTH - $indent;
	my $outtext;
	if ($textlen <= $widthavail) {
		$outtext = str_col($color,$prop);
	}
	else {
		my $line = "";
		my @lines = ();
		my $cur_widthavail = $widthavail;
		for my $word (split /\s/, $prop) {
			A_LABEL:
			if (length $word < $cur_widthavail) {
				$line .= $word . " ";
				$cur_widthavail -= (length($word) + 1);
			}
			elsif (length $word == $cur_widthavail) {
				$line .= $word . "\n";
				push @lines, $line;
				$line = "";
				$cur_widthavail = $widthavail;
			}
			# the word length exceeds space that left
			else {
				# maybe it's longer than available width?
				if (length $word > $widthavail) {
					$line .= (substr $word, 0, $cur_widthavail) . "\n";
					push @lines, $line;
					$line = "";
					$word = substr $word, $cur_widthavail;
					$cur_widthavail = $widthavail;
					goto A_LABEL;
				}
				# otherwise let's put in on a new line
				else {
					push @lines, ($line . "\n");
					$line = $word . " ";
					$cur_widthavail = $widthavail - (length ($word) + 1);
				}
			}
		}
		push @lines, $line if $line;
		# for (@lines) { print "[$_]" };
		# $outtext = join $indenttext,@lines;
		$outtext = join $indenttext,(map { str_col($color,$_) } @lines);
	}

	say str_col("green",">>")," "x9, str_col("green",$desc),
			" "x$pad, $outtext; #str_col($color,$outtext);
}

sub parse_and_print {
	my $data = shift;
	unless ($data) {
		say STDERR str_col("red", "No data supplied.");
		return 1;
	}

	my $j = decode_json $data;

	unless ($j) {
		# However it should die() by itself on decode_json.
		say STDERR "Error decoding the string, quitting.";
		exit 1;
	}

	my $repo_pref_sl = ($s_repo eq "sl" or $s_repo eq "all") ? 1 : 0;
	my $repo_pref_limbo = ($s_repo eq "limbo" or $s_repo eq "all") ? 1 : 0;
	# my $repo_pref_p = ($s_repo =~ /^(p|psl|pg)$/ or $s_repo eq "all") ? 1 : 0;
	my $repo_pref_p = ($h_repo{$s_repo}->{source} or $s_repo eq "all") ? 1 : 0;

	for my $el (sort {comp($a, $b)} @{$j}) {
		my $repo_cur_sl = 1 if $el->{repository_id} eq $h_repo{sl}->{API};
		my $repo_cur_limbo = 1 if $el->{repository_id} eq $h_repo{limbo}->{API};
		my $repo_cur_p = 1 if $el->{repository_id} eq $h_repo{p}->{API};
		my $repo_cur_foreign_p = 0; # 1 if not the "overlay" user wants

		if ($repo_cur_sl) {
			next unless $repo_pref_sl;
		}
		elsif ($repo_cur_limbo) {
			next unless $repo_pref_limbo;
		}
		elsif ($repo_cur_p) {
			next unless $repo_pref_p;
		}

		# note: if "all" option is supported then another check should be made
		# to remove from search results Sabayon packages that do not match
		# selected architecture

		# if Sabayon repository, filter out results with different branch
		if ($repo_cur_sl or $repo_cur_limbo) {
			next unless $el->{branch} == $branch;
			# let's leave this here, too
			next if $el->{is_source_repo};
		}
		elsif ($repo_cur_p) {
			next unless $el->{is_source_repo};
			# if the origin is not the one selected, don't skip it entirely
			# instead print it differently
			# this is the workaround: server sends limited number of results, eg.
			# if user wants "Sabayon" atoms and server sends 2 from the overlay
			# and 8 from Gentoo Portage, only those 2 would be printed even
			# if more of them are on the overlay
			# purpose of this is: make user aware "something" has been found
			# and the list is long enough so some atoms must've been skipped! yay
			if ($s_repo eq "psl") {
				$repo_cur_foreign_p = 1 unless ($el->{spm_repo} eq "sabayon");
			}
			elsif ($s_repo eq "pg") {
				$repo_cur_foreign_p = 1 unless ($el->{spm_repo} eq "gentoo");
			}
		}

		if ($quiet_mode) {
			if ($repo_cur_p) {
				_pnt_spm_atom($el->{atom}, $el->{spm_repo},
					quiet=>$quiet_mode, foreign=>$repo_cur_foreign_p);
			}
			else {
				say $el->{atom};
			}
		}
		else {
			if ($repo_cur_p && $repo_cur_foreign_p) {
				_pnt_spm_atom($el->{atom}, $el->{spm_repo},
					quiet=>$quiet_mode, foreign=>$repo_cur_foreign_p);
			}
			else {
				_pnt_pkg($el->{atom});
			}
			next if $repo_cur_foreign_p; # don't print properties
			_pnt_prop("Arch:", "bold blue", $el->{arch});
			_pnt_prop("Revision:", "bold blue", $el->{revision}) unless $repo_cur_p;
			_pnt_prop("Slot:", "bold blue", $el->{slot});
			_pnt_prop("Size:", "bold blue", $el->{size}) unless $repo_cur_p;
			_pnt_prop("Downloads:", "bold blue", $el->{ugc}->{downloads}) unless $repo_cur_p;
			_pnt_prop("Vote:", "bold blue", $el->{ugc}->{vote}) unless $repo_cur_p;
			_pnt_prop("spm_repo:", "bold blue", $el->{spm_repo} // "(null)");
			_pnt_prop_wrap("Description:", "magenta", $el->{description});
			_pnt_prop("License:", "cyan", $el->{license});
			_pnt_prop_wrap("Last change:", "bold blue", $el->{change} // "N/A");
			_pnt_prop("Repository:", "bold blue", $el->{repository_id}) if $s_repo eq "all";
		}
	}

	unless ($quiet_mode) {
		say str_col("green",">>")," "x2, str_col("bold blue", "Keyword:  "),
			str_col("magenta",$key);
	}
	say str_col("yellow", "\nalternative ways to search packages: use equo (equo search,\n",
		"equo match, ...), Sulfur or visit http://packages.sabayon.org");
}

######## parse_cmdline ########

sub _get_opts {
	# arg: for example @h_args
	# populate keys, in order
	my @keys = ();
	while (defined (my $x = shift)) {
		push @keys, $x unless ref $x;
	}
	@keys;
}

sub parse_cmdline {
	my $params_ok = 1;
	while (my $arg = shift) {
		given ($arg) {
			when(["--help", "-h"]) {
					my ($arch_opts, $type_opts, $order_opts, $repo_opts);
					$arch_opts = join "|",_get_opts(@h_arch);
					$type_opts = join "|",_get_opts(@h_type);
					$order_opts = join "|",_get_opts(@h_order);
					$repo_opts = join "|",_get_opts(@h_repo);
				say "This is a Perl script to query packages using packages.sabayon.org.\n" ,
					"For interactive use run this script without any parameters.\n" ,
					"Usage:\n" ,
					"\t[--arch $arch_opts] [--order $order_opts] [-q|--quiet]\n" ,
					"\t[--type $type_opts] [--repo $repo_opts]  keyword\n" ,
					"\tadditional options: --color - enable colorized output (default), " ,
					"--nocolor - disable colorized output, ",
					"--quiet/-q - produce less output\n",
					"Default values: $s_arch, $s_order, $s_type, $s_repo.\n",
					"example usage: $0 --arch x86 --order size pidgin\n" ,
					"also this is correct: $0 pidgin --arch x86 --order size";
				say "\n--type:";
				for (_get_opts(@h_type)) {
					say "$_\t\t", $h_type{$_}->{desc};
				}
				say "\n--order:";
				for (_get_opts(@h_order)) {
					say "$_\t\t", $h_order{$_}->{desc};
				}
				say "\n--repo:";
				for (_get_opts(@h_repo)) {
					say "$_\t\t", $h_repo{$_}->{desc};
				}
				exit 0;
			}
			when ("--arch") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_arch) ]) {
					$s_arch = $arg;
				}
				else {
					say STDERR "Wrong parameters after --arch." ,
						"Currently selected is $s_arch.";
					$params_ok = 0;
				}
			}
			when ("--order") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_order) ]) {
					$s_order = $arg;
				}
				else {
					say STDERR "Wrong parameters after --order.\n" ,
						"Currently selected is $s_order.";
					$params_ok = 0;
				}
			}
			when ("--type") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_type) ]) {
					$s_type = $arg;
				}
				else {
					say STDERR "Wrong parameters after --type.\n" ,
						"Currently selected is $s_type.";
					$params_ok = 0;
				}
			}
			when ("--repo") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_repo) ]) {
					$s_repo = $arg;
				}
				else {
					say STDERR "Wrong parameters after --repo.\n" ,
						"Currently selected is $s_repo.";
					$params_ok = 0;
				}
			}
			when ("--color") {
				$use_colour = 1;
			}
			when ("--nocolor") {
				$use_colour = 0;
			}
			when (["--quiet", "-q"]) {
				$quiet_mode = 1;
			}
			# key
			if (defined $key) {
				say STDERR "You can specify only one keyword (at: $arg).";
				if ($arg =~ /^-/) {
					say STDERR "Tip: search term $arg begins with a `-' character.\n" ,
						"Maybe you gave an unknown parameter and it was " ,
						"interpreted as search term?";
				}
				$params_ok = 0;
				last;
			}
			else {
				$key = $arg;
			}
		}
	}

	unless (defined $key) {
		say STDERR "What are you looking for?";
		$params_ok = 0;
	}

	if (length $key < 3 or length $key > 100) {
		say STDERR "Search term should contain no less that three and no more than " ,
			"one hundred letters.";
		exit 1;
	}

	unless(package_name_check_and_warn($key)) {
		$params_ok = 0;
	}

	if ($key =~ /^-/) {
		say STDERR "Tip: search term $key begins with a `-' character.\n" .
			"Maybe you wanted to give an unknown parameter and it was interpreted " ,
			"as search term?";
	}

	unless ($params_ok) {
		say STDERR "\nSpecify correct parameters. Try -h or --help or run this script\n" ,
			"without any parameters for interactive usage. Exiting!";
		exit 1;
	}
}

######## interactive_ui ########

sub _pnt_set_opt {
	my $s_r = shift or die "no arg!"; # ref to variable like $s_arch
	my $h_r = shift or die "no arg!"; # ref to variable like @h_arch (array!)
	my $print_opt = shift; # print description with option, too?
	my $s_tmp = $$s_r;
	my %h_tmp = @$h_r;

	if ($print_opt) {
		say "currently selected: $s_tmp (", $h_tmp{$s_tmp}->{desc}, ")";
	}
	else {
		say "currently selected: ", $h_tmp{$s_tmp}->{desc};
	}

	# populate keys, in order
	my @keys = ();
	for (@$h_r) {
		push @keys, $_ unless ref $_; # push only strings - options
	}

	my $l = 'a';
	for my $opt (@keys) {
		if ($print_opt) {
			say "[$l] $opt (", $h_tmp{$opt}->{desc}, ")";
		}
		else {
			say "[$l] ", $h_tmp{$opt}->{desc};
		}
		$l++;
	}

	my $resp = <STDIN>;
	chomp $resp;
	if ($resp lt 'a' or $resp ge $l) {
		# do nothing if no argument/out of range
	}
	else {
		$$s_r = $s_tmp = $keys[ord ($resp) - ord ('a')];
	}

	if ($print_opt) {
		say "selected: $s_tmp (", $h_tmp{$s_tmp}->{desc}, ")";
	}
	else {
		say "selected: ", $h_tmp{$s_tmp}->{desc};
	}
	$s_tmp;
}

sub interactive_ui {
	say "Hello! This is a Perl script to query packages using packages.sabayon.org.\n",
		"Type a number or letter and enter to change any of these settings\n",
		"(for example, 1<enter> to change architecture type).\n",
		"Note: invoke this script with -h or --help for help on non-interactive usage.";

	while (1) {
		say "\n[1] arch: $s_arch (x86, amd64)\n",
			"[2] search type: $s_type (", $h_type{$s_type}->{desc}, ")\n",
			"[3] order: $s_order (", $h_order{$s_order}->{desc}, ")\n",
			"[4] repository: " . $h_repo{$s_repo}->{desc} . "\n",
			"[c] color: " . ($use_colour ? "enabled" : "disabled") . "\n",
			"[t] quiet: " . ($quiet_mode ? "enabled" : "disabled") . "\n",
			"[q] quit\n",
			"(any other) continue";
		$key = <STDIN>;
		chomp $key;
		say "";
		given ($key) {
			when ("1") {
				say "select architecture:";
				_pnt_set_opt(\$s_arch, \@h_arch, 0);
			}
			when ("2") {
				say "select search type:";
				_pnt_set_opt(\$s_type, \@h_type, 0);
			}
			when ("3") {
				say "select sort order:";
				_pnt_set_opt(\$s_order, \@h_order, 1);
			}
			when ("4") {
				say "select repository:";
				_pnt_set_opt(\$s_repo, \@h_repo, 0);
			}
			when ("c") {
				$use_colour = !$use_colour;
			}
			when ("t") {
				$quiet_mode = !$quiet_mode;
			}
			when ("q") {
				say "Bye!";
				exit 0;
			}
			# default
			last;
		}
	}

	say "What are you looking for? Type your search term.";
	if (length $key) {
		say "(If it is $key, just press Enter.)";
	}

	while (1) {
		my $new_key = <STDIN>;
		chomp $new_key;
		# for "If it is $key, just press Enter." - pressed Enter without typing anything:
		if (length $new_key == 0) {
			$new_key = $key;
			$key = "";
		}
		if (length $new_key < 3) {
			say "Too short! Try again or type Ctrl+C to abort.";
		}
		elsif(length $new_key > 100) {
			say "Too long! Try again or type Ctrl+C to abort.";
		}
		elsif (!package_name_check_and_warn($new_key)) {
			say "Try again or type Ctrl+C to abort.";
		}
		else {
			$key = $new_key;
			last;
		}
	}
}

######## UI helpers ########

sub str_col {
	my $col = shift or return "";
	if ($use_colour) {
		return color($col) . (join "",@_) . color("reset");
	}
	else {
		return join "",@_;
	}
}

sub package_name_check_and_warn {
	# 1 - ok, 0 - not ok
	my $arg = shift or return 0;
	if ($s_type eq "path") {
		if ($arg =~ /^\//) {
			return 1;
		}
		else {
			say STDERR "If you search by path, provide full path (starting with /).";
			return 0;
		}
	}
	else {
		if ($arg =~ /^\//) {
			say STDERR str_col("red","Info: "),
				qq{provided package name begins with a slash, but "path" search },
				qq{type is not selected.\nIf you want to search by path, specify },
				qq{correct option.\n};
		}
	}
	if (($s_type eq "pkg" or $s_type eq "match") and $arg =~ /:/) {
		# A colon is part if the API, so disallow its usage here...
		say STDERR qq{The package name is invalid. It should not contain any },
			qq{":" characters.};
		return 0;
	}
	1;
}

######## compare functions ########

sub comp_size {
	my ($a,$b) = @_;

	my $a_num = 0;
	my $b_num = 0;
	my $a_rest = "";
	my $b_rest = "";

	if($a =~ /^([\d.]+)(.*)/) {
		$a_num = $1;
		$a_rest = $2;
	}
	if($b =~ /^([\d.]+)(.*)/) {
		$b_num = $1;
		$b_rest = $2;
	}

	given($a_rest) {
		$a_num *= 1024 when ("MB");
		$a_num *= 1048576 when ("GB"); # what?
	}
	given($b_rest) {
		$b_num *= 1024 when ("MB");
		$b_num *= 1048576 when ("GB");
	}
	return $a_num <=> $b_num;
}

sub comp {
	my ($a,$b) = @_;
	given ($s_order) {
		# The server does not always sort for all sort options currently,
		# so it is handled in this script (besides its own sort option).
		when ("alph") {
			return ($a->{atom} cmp $b->{atom});
		}
		when ("size") {
			return comp_size ( $b->{size}, $a->{size} ); # desc
		}
		when ("vote") {
			return ($b->{ugc}->{vote} <=> $a->{ugc}->{vote});
		}
		when ("downloads") {
			return ($b->{ugc}->{downloads} <=> $a->{ugc}->{downloads});
		}
		# default
		return 0;
	}
}
