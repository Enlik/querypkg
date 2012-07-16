package App::Querypkg::Core;

use warnings;
use strict;
use 5.010;
use Carp;
use LWP::UserAgent;
use URI::Escape;
use JSON::XS;

# a simple interface to packages.sabayon.org
# (C) 2011-2012 by Enlik <poczta-sn at gazeta . pl>
# license: MIT

# note: those "API keys" mean "input" or "output" API related things
# arrays to preserve order as specified, hashes are below
my @h_arch = (
	amd64 => { API => 'amd64', desc => 'amd64' },
	x86 => { API => 'x86', desc => 'x86' },
	arm => { API => 'armv7l', desc => 'armv7l' }
	# "arch" if Portage selected: hard-coded in make_URI
);
my @h_type = (
	pkg => { API => 'pkg', desc => 'package search' },
	desc => { API => 'desc', desc => 'description' },
	path => { API => '', desc => 'path', prepend => 1 },
	use => { API => 'u:', desc => 'USE flag', prepend => 1},
	lib => { API => 'sop:', desc => 'package that provides a library (.so)', prepend => 1 },
	match => { API => 'match', desc => 'package matching' },
	set => { API => '@', desc => 'package set, for example @xfce', prepend => 1 }
);
my @h_order = (
	alph => { API => 'alphabet', desc => 'alphabetically' },
	vote => { API => 'vote', desc => 'by votes' },
	downloads => { API => 'downloads', desc => 'by downloads' },
	size => { API => '', desc => 'by size' },
	date => { API => '', desc => 'by "date" field' }
);
my @h_repo = (
	sl => { API => 'sabayonlinux.org', desc => 'sabayonlinux.org (Sabayon repository)' },
	we => { API => 'sabayon-weekly',
		desc => 'sabayon-weekly (default repository for main/official releases)' },
	limbo => { API => 'sabayon-limbo', desc => 'sabayon-limbo (Sabayon testing repository)' },
	p => { API => 'portage', desc => 'Portage (with Sabayon overlays)', source => 1 },
	psl => { API => 'portage', desc => 'Sabayon overlays', source => 1 },
	pg => { API => 'portage', desc => 'Portage' , source => 1 }
	# since number of results is limited, I think "all" is useless (and see "note" below)
	#all => { API => undef, desc => 'sabayonlinux.org, Limbo and Portage' }
);

sub new {
	my $class = shift;
	my $self = { };
	bless $self, $class;
	$self->_init;
	$self;
}

my %h_arch  = @h_arch;
my %h_type  = @h_type;
my %h_order = @h_order;
my %h_repo  = @h_repo;

use constant {
	PKG_NAME_TOO_SHORT   => -1,
	PKG_NAME_TOO_LONG    => -2,
	PKG_NAME_OK          => 0
};

sub _init {
	my $self = shift;
	# set values like: $self->{valid_values}->{arch} = [ x86 ... ]
	$self->{valid_params}->{arch}  = [ _get_opts(@h_arch) ];
	$self->{valid_params}->{type}  = [ _get_opts(@h_type) ];
	$self->{valid_params}->{order} = [ _get_opts(@h_order) ];
	$self->{valid_params}->{repo}  = [ _get_opts(@h_repo) ];
	$self->{api}->{arch}  = \@h_arch;
	$self->{api}->{type}  = \@h_type;
	$self->{api}->{order} = \@h_order;
	$self->{api}->{repo}  = \@h_repo;
	# misc. options
	$self->{branch} = 5; # not used on Portage search
	$self->{iter_pos} = undef;
	$self->{server_results_limit} = 10;
	# default options
	$self->set_req_params(
		arch  => 'amd64',
		type  => 'pkg',
		order => 'alph',
		repo  => 'sl'
	);
}

########### parameter handling ###########

sub set_req_params {
	my $self = shift;
	my %params = @_;

	for my $p (keys %params) {
		$self->_set_req_param ($p, $params{$p});
	}
}

sub get_req_param {
	my $self = shift;
	my $param = shift;

	unless ($self->{valid_params}->{$param}) {
		croak "Unknown parameter '$param'"
	}

	$self->{sel_params}->{$param};
}

# Returns a hash ref for a parameter for currently selected option.
# Primarily used to get description for an option. So, instead of:
# %h_arch = $obj->get_API_array('arch');
# $s_arch = $obj->get_req_param('arch');
# $cur_arch_desc = $h_desc{$s_arch}->{desc}
# one can do this:
# $cur_arch_desc = $obj->get_API_sel()->{desc}.
sub get_API_sel {
	my $self = shift;
	my $param = shift;

	my %h   = $self->get_API_array( $param );
	my $sel = $self->get_req_param( $param );
	$h{$sel};
}

# Return an array, not hash becase order of elements can be useful/important.
sub get_API_array {
	my $self = shift;
	my ($param, $get_opts_only) = @_;
	unless (defined $self->{api}->{$param}) {
		croak "Unknown parameter '$param'"
	}

	if ($get_opts_only) {
		$self->_get_opts( @{ $self->{api}->{$param} } )
	}
	else {
		@{ $self->{api}->{$param} }
	}
}

sub _set_req_param {
	my $self = shift;
	my ($param, $value) = @_;

	unless ($self->{valid_params}->{$param}) {
		croak "Unknown parameter '$param'"
	}

	my @ok = @{ $self->{valid_params}->{$param} };
	unless ($value ~~ @ok) {
		croak "Unknown parameter '$value' for '$param'. Valid values: ",
			join (", ", @ok)
	}

	$self->{sel_params}->{$param} = $value;
}

sub _get_opts {
	# arg: for example @h_args
	grep { not ref } @_; # take only strings - options
}

########### error messages handling code ###########

sub geterr {
	my $self = shift;
	$self->{error} // "(unknown)" # "success" would be more funny I know
}

sub _seterr {
	my $self = shift;
	my $msg = shift;
	$self->{error} = $msg;
}

########### network related stuff, URI handling ###########

# Sets an URI and returns it too in case it'd be useful.
# Keyword checking (with package_name_check()) is done in get_data()
# so this allows to generate URIs for any keyword.
sub make_URI {
	my $self = shift;
	my $key = shift or croak "No argument for make_URI!";
	my $key_ok = uri_escape $key;
	my $URI = "http://packages.sabayon.org/search?q=";
	my $s_type = $self->get_req_param('type');
	if ($h_type{$s_type}->{prepend}) {
		$URI .= $h_type{$s_type}->{API} . $key_ok;
	}
	else {
		$URI .= $key_ok;
		$URI .= "&t=" . $h_type{$s_type}->{API};
	}

	my $s_repo = $self->get_req_param('repo');
	my $s_arch = $self->get_req_param('arch');
	unless ($s_repo eq "all") {
		if ($h_repo{$s_repo}->{source}) {
			$URI .= "&a=arch";
		}
		else {
			my $branch = $self->{branch};
			$URI .= "&a=" . $h_arch{$s_arch}->{API};
			$URI .= "&r=" . $h_repo{$s_repo}->{API};
			$URI .= "&b=$branch";
		}
	}
	# empty means "internal" sort order, not provided by the server
	my $s_order = $self->get_req_param('order');
	($URI .= "&o=" . $h_order{$s_order}->{API}) if $h_order{$s_order}->{API};
	$URI .= "&render=json";
	$self->_set_uri($URI);
	$self->_set_keyword($key);
	$URI;
}

sub get_uri {
	my $self = shift;
	$self->{uri} // ""
}

# Get keyword/search term/atom.
sub get_keyword {
	my $self = shift;
	$self->{keyword} // ""
}

sub _set_uri {
	my $self = shift;
	my $uri = shift;
	$self->{uri} = $uri;
}

sub _set_keyword {
	my $self = shift;
	my $keyw = shift;
	$self->{keyword} = $keyw;
}

# returns a true value on success, false otherwise; sets error message
sub get_data {
	my $self = shift;
	my $URI = $self->get_uri();
	my $str;

	unless ($URI) {
		$self->_seterr( "URI hasn't been defined." );
		return;
	}

	my $check = $self->package_name_check( $self->get_keyword(), undef );
	unless ($check == PKG_NAME_OK) {
		my $desc =
			$check == PKG_NAME_TOO_LONG
			? "name too long"
			: $check == PKG_NAME_TOO_SHORT
			? "name too short"
			: "unknown (code $check)";
		$self->_seterr( "Invalid package name: $desc" );
		return;
	}

	if (1) {
		my $ua = LWP::UserAgent->new;
		my $s_type = $self->get_req_param('type');
		$ua->timeout( $s_type eq 'path' ? 30 : 20 );
		$ua->env_proxy;

		my $resp = $ua->get($URI);
		unless($resp->is_success) {
			$self->_seterr( "Error fetching data: " . $resp->status_line );
			return;
		}

		$str = $resp->content;
		if (!$str) {
			$self->_seterr( "Empty or invalid response" );
			return
		}
	}
	else {
		# debugging
		$str = qx(cat w/bla);
	}

	my $j;
	eval {
		$j = decode_json $str;
	};

	if ($@) {
		my $s = "Error decoding the string: $@";
		chomp $s;
		$self->_seterr( $s );
		return;
	}

	$self->{json_data} = [ sort { $self->_comp($a, $b) } @$j ];
	$self->{iter_pos} = 0;
	$self->{result_counter} = 0;
	return 1;
}

########### data processing ###########

sub next_pkg {
	my $self = shift;
	my $j;

	unless (defined $self->{iter_pos}) {
		croak "No data; get_data() not called?"
	}

	$j = $self->{json_data};

	my $s_arch  = $self->get_req_param('arch');
	my $s_type  = $self->get_req_param('type');
	my $s_order = $self->get_req_param('order');
	my $s_repo  = $self->get_req_param('repo');
	my $branch  = $self->{branch};

	my $repo_pref_sl = ($s_repo eq "sl" or $s_repo eq "all") ? 1 : 0;
	my $repo_pref_limbo = ($s_repo eq "limbo" or $s_repo eq "all") ? 1 : 0;
	my $repo_pref_weekly = ($s_repo eq "we" or $s_repo eq "all") ? 1 : 0;
	my $repo_pref_p = ($h_repo{$s_repo}->{source} or $s_repo eq "all") ? 1 : 0;

	while (1) {
		my $el = $j->[ $self->{iter_pos} ];
		last unless defined $el;
		$self->{iter_pos}++;

		my $repo_cur_sl = 1 if $el->{repository_id} eq $h_repo{sl}->{API};
		my $repo_cur_limbo = 1 if $el->{repository_id} eq $h_repo{limbo}->{API};
		my $repo_cur_weekly = 1 if $el->{repository_id} eq $h_repo{we}->{API};
		my $repo_cur_p = 1 if $el->{repository_id} eq $h_repo{p}->{API};
		my $repo_cur_foreign_p = 0; # 1 if not the "overlay" user wants
		my %meta_items = ();

		# count also skipped
		$self->{result_counter}++;

		if ($repo_cur_sl) {
			next unless $repo_pref_sl;
		}
		elsif ($repo_cur_limbo) {
			next unless $repo_pref_limbo;
		}
		elsif ($repo_cur_weekly) {
			next unless $repo_pref_weekly;
		}
		elsif ($repo_cur_p) {
			next unless $repo_pref_p;
		}

		# note: if "all" option is supported then additional check should be
		# considered to remove Sabayon packages from search results that
		# do not match selected architecture

		if ($repo_cur_sl or $repo_cur_limbo or $repo_cur_weekly) {
			# if Sabayon repository, filter out results with different branch
			next unless $el->{branch} == $branch;
			# sometimes results from server are naughty, so:
			next unless $el->{arch} eq $h_arch{$s_arch}->{API};
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
				# Keep in mind there are two Sabayon overlays.
				$repo_cur_foreign_p = 1 if ($el->{spm_repo} eq "gentoo");
			}
			elsif ($s_repo eq "pg") {
				$repo_cur_foreign_p = 1 unless ($el->{spm_repo} eq "gentoo");
			}
		}

		for my $item (@{$el->{meta_items}}) {
			if (!defined $item->{id}) {
				last;
			}
			given ($item->{id}) {
				when ("details") {
					$meta_items{details} =
						"http://packages.sabayon.org" . $item->{url};
				}
				when ("homepage") {
					$meta_items{homepage} = $item->{url};
				}
			}
		}

		my %ret = (
			atom        => $el->{atom},
			is_source   => $repo_cur_p,
			arch        => $el->{arch},
			slot        => $el->{slot},
			spm_repo    => $el->{spm_repo}, # can be undef
			homepage    => $meta_items{homepage}, # can be undef
			description => $el->{description},
			date        => $el->{date},
			license     => $el->{license},
			change      => $el->{change}, # can be undef
			repository  => $el->{repository_id},
			url_details => $meta_items{details} # can be undef
		);

		if ($repo_cur_p) {
			# source repository
			$ret{foreign}  = $repo_cur_foreign_p; # from another overlay
		}
		else {
			$ret{revision}  = $el->{revision};
			$ret{size}      = $el->{size};
			$ret{downloads} = $el->{ugc}->{downloads};
			$ret{vote}      = $el->{ugc}->{vote};
		}

		return \%ret;
	}
}

sub server_results_limit {
	my $self = shift;
	$self->{server_results_limit}
}

# Useful to print something like:
#my $msg = "The number of items sent by the server equals the ";
#		$msg .= "server-side limit of 10.\nIf there are more results, ";
#		$msg .= "they were omitted.";
sub limit_reached {
	my $self = shift;
	unless (defined $self->{result_counter}) {
		croak "result_counter not set"
	}
	return ($self->{result_counter} == $self->server_results_limit)
}

# Parameters: $key (key to check) and $is_set (true - it's set, false - it's
# not a set, undefined - get from settings).
sub package_name_check {
	my $self = shift;
	my ($key, $is_set) = @_;
	croak "missing argument to package_name_check"
		unless defined $key;

	$is_set //= $self->get_req_param( 'type' ) eq "set";
	my $len = length $key;
	# Server checks length limits with "modifiers". Right now we make only
	# a special check for search type set.
	$len += 1 if $is_set;
	if ($len < 2) {
		return PKG_NAME_TOO_SHORT
	}
	if ($len > 64) {
		return PKG_NAME_TOO_LONG
	}

	PKG_NAME_OK;
}

######## compare functions ########

sub _comp_size {
	my $self = shift;
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
		when ("MB") {
			$a_num *= 1024
		}
		when ("GB") {
			$a_num *= 1048576
		}
		default {
			die "Unrecognized size suffix '$a_rest'"
		}
	}
	given($b_rest) {
		when ("MB") {
			$b_num *= 1024
		}
		when ("GB") {
			$b_num *= 1048576
		}
		default {
			die "Unrecognized size suffix '$b_rest'"
		}
	}
	return $a_num <=> $b_num;
}

sub _comp {
	my $self = shift;
	my ($a,$b) = @_;
	given ($self->get_req_param('order')) {
		# The server does not always sort for all sort options currently,
		# so it is handled in this script (besides its own sort option).
		when ("alph") {
			return ($a->{atom} cmp $b->{atom});
		}
		when ("size") {
			return $self->_comp_size ( $b->{size}, $a->{size} ); # desc
		}
		when ("vote") {
			return ($b->{ugc}->{vote} <=> $a->{ugc}->{vote});
		}
		when ("downloads") {
			return ($b->{ugc}->{downloads} <=> $a->{ugc}->{downloads});
		}
		when ("date") {
			return ($b->{mtime} <=> $a->{mtime});
		}
		# default
		return 0;
	}
}

=head1 NAME

App::Querypkg::Core - core modules for querypkg

=head1 DESCRIPTION

Internal module for querypkg.

=cut

1;
