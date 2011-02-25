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

# API options: $o_var = ( option => { API => 'API key', desc => 'description' } )
# arrays to preserve order as specified, hashes are below
my @h_arch = (	amd64 => { API => 'amd64', desc => 'amd64' },
				x86 => { API => 'x86', desc => 'x86' } );
my @h_type = (	pkg => { API => 'pkg', desc => 'package search' },
				match => { API => 'match', desc => 'package matching (>=app-foo/foo-1.2.3)' },
				desc => { API => 'desc', desc => 'description' },
				path => { API => 'file', desc => 'path' },
				lib => { API => 'lib', desc => 'library (.so) search' } );
my @h_order = ( alph => { API => 'alphabet', desc => 'alphabetically' },
				vote => { API => 'vote', desc => 'by votes' },
				downloads => { API => 'downloads', desc => 'by downloads' },
				size => { API => 'alphabet', desc => 'by size' } );

my %h_arch = @h_arch;
my %h_type = @h_type;
my %h_order = @h_order;

# default values
my $s_arch = 'amd64';
my $s_type = 'pkg';
my $s_order = 'alph';

# another values
my $branch = "5";
my $repo = "sabayonlinux.org";
my $order_by_size = $s_order eq 'size' ? 1 : 0;
my $use_colour = 1;

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
	my $URI = "http://packages.sabayon.org/search?q=$key_ok";
	$URI .= "&a=" . $h_arch{$s_arch}->{API};
	$URI .= "&t=" . $h_type{$s_type}->{API};
	# this seems not to work
	($URI .= "&o=" . $h_order{$s_order}->{API}) unless ($order_by_size);
	$URI .= "&b=$branch";
	$URI .= "&render=json";
	$URI;
}

######## get_data ########

sub get_data {
	my $URI = shift or return;
	my $str;
	# my $_file = 'd'; # local file with data, set for *debugging* purposes
	my $_file;
	if (defined $_file) {
		say str_col("green", ">>  "), str_col("red", "@@ "),
			str_col("green", "Reading data from file...");
		$str = `cat "$_file"`;
	}
	else {
		my $ua = LWP::UserAgent->new;
		$ua->timeout(15);
		$ua->env_proxy;
		
		say str_col("green", ">>  "), str_col("red", "@@ "),
			str_col("green", "Please wait, downloading data...");
		my $resp = $ua->get($URI);
		unless($resp->is_success) {
			say "Error fetching data: " . $resp->status_line;
			exit 1;
		}

		$str = $resp->content;
	}
	$str;
}

######## parse_and_print ########

sub _pnt_pkg {
	my $atom = shift;
	say str_col("green",">>      "), str_col("red","@@ Package: "),
			str_col("bold white",$atom);
}

sub _pnt_prop {
	my $desc = shift;
	my $color = shift;
	my $prop = shift;
	say str_col("green",">>")," "x9, str_col("green","$desc\t"),
			str_col($color,$prop);
}

sub parse_and_print {
	my $data = shift;
	unless ($data) {
		say str_col("red", "No data supplied.");
		return 1;
	}

	my $j = decode_json $data;
	
	unless ($j) {
		# However it should die() by itself on decode_json.
		say "Error decoding the string, quitting.";
		exit 1;
	}
	
	for my $el (sort {comp($a, $b)} @{$j}) {
		# say "→",$el->{is_source_repo},"|",$el->{branch},"←";
		next unless $el->{branch} == $branch;
		# as for now only binary packages are supported
		# filtering out results with branch != 5 seems to do the same, but let's
		# leave it here, too
		next if $el->{is_source_repo};
		# for now let's omit Limbo, too
		next unless $el->{repository_id} eq $repo;
		_pnt_pkg($el->{atom});
		_pnt_prop("Arch:", "bold blue", $el->{arch});
		_pnt_prop("Revision:", "bold blue", $el->{revision});
		_pnt_prop("Slot:", "bold blue", $el->{slot});
		_pnt_prop("Size:", "bold blue", $el->{size});
		_pnt_prop("Downloads:", "bold blue", $el->{ugc}->{downloads});
		_pnt_prop("Vote:", "bold blue", $el->{ugc}->{vote});
		_pnt_prop("spm_repo:", "bold blue", ($el->{spm_repo} // "(null)"));
		_pnt_prop("License:", "bold blue", $el->{license});
		_pnt_prop("Description:", "magenta", $el->{description});
		# _pnt_prop("repository_id:", "bold blue", $el->{repository_id});
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

sub _pnt_opts {
	my $s_r = shift or die "no arg!"; # ref to variable like $s_arch
	my $h_r = shift or die "no arg!"; # ref to variable like @h_arch (array!)
	my $print_opt = shift; # print description with option, too?
	my $s_tmp = $$s_r;
	my %h_tmp = @$h_r;

	# populate keys, in order
	my @keys = ();
	for (@$h_r) {
		push @keys, $_ unless ref $_;
	}

	my @opts;
	my @help;

	my $l;
	for my $opt (@keys) {
		push @opts, $opt;
		if ($print_opt) {
			say "[$l] $opt (", $h_tmp{$opt}->{desc}, ")";
		}
		else {
			say "[$l] ", $h_tmp{$opt}->{desc};
		}
	}

	my $resp = <STDIN>;
	chomp $resp;
	if ($resp lt 'a' or $resp ge $l) {
		# do nothing
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

sub parse_cmdline {
	my $params_ok = 1;
	while (my $arg = shift) {
		given ($arg) {
			when(["--help", "-h"]) {
					my ($arch_opts, $type_opts, $order_opts);
					$arch_opts = join "|",_get_opts(@h_arch);
					$type_opts = join "|",_get_opts(@h_type);
					$order_opts = join "|",_get_opts(@h_order);
				say "This is a Perl script to query packages using packages.sabayon.org.\n" ,
					"For interactive use run this script without any parameters.\n" ,
					"Usage:\n" ,
					"\t[--arch $arch_opts] [--order $order_opts]\n" ,
					"\t[--type $type_opts] keyword\n" ,
					"\tadditional options: --color - enable colorized output (default), " ,
					"--nocolor - disable colorized output\n",
					"Default values: $s_arch, $s_order, $s_type.\n",
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
				exit 0;
			}
			when ("--arch") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_arch) ]) {
					$s_arch = $arg;
				}
				else {
					say "Wrong parameters after --arch." ,
						"Currently selected is $s_arch.";
					$params_ok = 0;
				}
			}
			when ("--order") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_order) ]) {
					$s_order = $arg;
					$order_by_size = $s_order eq 'size' ? 1 : 0;
				}
				else {
					say "Wrong parameters after --order.\n" ,
						"Default: $s_order.";
					$params_ok = 0;
				}
			}
			when ("--type") {
				$arg = shift;
				if($arg ~~ [ _get_opts(@h_type) ]) {
					$s_type = $arg;
				}
				else {
					say "Wrong parameters after --type.\n" ,
						"Default: $s_type.";
					$params_ok = 0;
				}
			}
			when ("--color") {
				$use_colour = 1;
			}
			when ("--nocolor") {
				$use_colour = 0;
			}
			# key
			if (defined $key) {
				say "You can specify only one keyword (at: $arg).";
				if ($arg =~ /^-/) {
					say "Tip: search term $arg begins with a `-' character.\n" ,
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
		say "What are you looking for?";
		$params_ok = 0;
	}

	if (length $key < 3 or length $key > 100) {
		say "Search term should contain no less that three and no more than " ,
			"one hundred letters.";
		exit 1;
	}

	if ($key =~ /^-/) {
		say "Tip: search term $key begins with a `-' character.\n" .
			"Maybe you wanted to give an unknown parameter and it was interpreted " ,
			"as search term?";
	}

	unless ($params_ok) {
		say "\nSpecify correct parameters. Try -h or --help or run this script\n" ,
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
		push @keys, $_ unless ref $_;
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
		# do nothing
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
			"[c] color: " . ($use_colour ? "enabled" : "disabled") . "\n",
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
				$order_by_size = $s_order eq 'size' ? 1 : 0;
			}
			when ("c") {
				$use_colour = !$use_colour;
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
			say "Too short! Try once again or type Ctrl+C to abort.";
		}
		elsif(length $new_key > 100) {
			say "Too long! Try once again or type Ctrl+C to abort.";
		}
		else {
			$key = $new_key;
			last;
		}
	}
}

######## UI helper ########

sub str_col {
	my $col = shift or return ();
	if ($use_colour) {
		return color($col), @_, color("reset");
	}
	else {
		return @_;
	}
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
	if($order_by_size) {
		comp_size ( $b->{size}, $a->{size} ); # desc
	}
	elsif ($s_order eq "vote") {
		$b->{ugc}->{vote} <=> $a->{ugc}->{vote};
	}
	elsif ($s_order eq "downloads") {
		$b->{ugc}->{downloads} <=> $a->{ugc}->{downloads};
	}
	else {
		0;
	}
}
