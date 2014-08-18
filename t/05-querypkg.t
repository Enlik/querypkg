use strict;
use warnings;
use JSON::XS;

# a simple interface to packages.sabayon.org - tests (JSON, ...)
# (C) 2011-2012, 2014 by Enlik <poczta-sn at gazeta . pl>
# license: MIT

use Test::More tests => 3;

#########################

# Stubs and whatnot.

{
	package App::Querypkg::Stub::Fetch;
	use base 'App::Querypkg';
	our $json_str;

	sub _fetch {
		$json_str
	}
}

sub gen_json {
	# Generate JSON string for one or more packages, accepting
	# default parameters.
	# gen_json({atom => "abc"}, ...)

	my @pkgs;

	my %defaults = (
		atom          => "virtual/whatever-1",
		arch          => "amd64",
		size          => "0.2MB",
		slot          => "0",
		repository_id => "sabayon-weekly",
		spm_repo      => "gentoo",
		branch        => "5"
	);

	for my $o (@_) {
		my %all = ( %defaults, %$o );
		push @pkgs, \%all;
	}

	$App::Querypkg::Stub::Fetch::json_str = encode_json( \@pkgs );
}

# Tests for features that don't require network access
# (_fetch is a stub, above).

subtest "basic get_data() tests" => sub {
	plan tests => 3;
	my $ret;

	my $c = App::Querypkg::Stub::Fetch->new;
	$c->make_URI( "something" );

	undef $App::Querypkg::Stub::Fetch::json_str;
	$ret = $c->get_data;
	ok( !$ret, "get_data() return value on _fetch() failure" );

	$App::Querypkg::Stub::Fetch::json_str = "<xml>Huh?</xml>";
	$ret = $c->get_data;
	ok( !$ret, "get_data() return value: invalid JSON" );
	like( $c->geterr(), qr/^Error decoding the string: /,
		"get_data() error message: invalid JSON");
};

subtest "results number test" => sub {
	plan tests => 10;
	my $ret;

	my $c = App::Querypkg::Stub::Fetch->new;
	$c->make_URI( "anything" );
	my $limit = $c->server_results_limit;

	my $test_n_results = sub {
		my $expected_n_of_results = shift;
		my $expected_if_limit_reached = shift;
		my @specs = @_;

		my $num_elements = @_;

		gen_json(@specs);
		$c->set_req_params( repo => "we" );
		$ret = $c->get_data();
		my $cnt = 0;
		$cnt++ while $c->next_pkg;

		if( $expected_if_limit_reached ) {
			ok( $c->limit_reached, "limit reached ($num_elements elements)" );
		}
		else {
			ok( !$c->limit_reached, "limit not reached ($num_elements elements)" );
		}

		is( $cnt, $expected_n_of_results,
			"number of results is $expected_n_of_results ($num_elements " .
			"elements received)" );
	};

	my @specs;

	# no results
	$test_n_results->(0, 0);

	# two results
	@specs = map {
		{atom => "ctg/pkg-$_", repository_id => "sabayon-weekly"}
	} (1..2);
	$test_n_results->(2, 0, @specs);

	# two results, one match
	@specs = (
		{atom => "a/b", repository_id => "sabayonlinux.org"},
		{atom => "c/d", repository_id => "sabayon-weekly"}
	);
	$test_n_results->(1, 0, @specs);

	# $limit results, all matches
	@specs = map {
		{atom => "ctg/pkg-$_", repository_id => "sabayon-weekly"}
	} (1..$limit);
	$test_n_results->($limit, 1, @specs);

	# $limit results, three matches
	@specs = map {
		{atom => "ctg/pkg-$_", repository_id => "sabayonlinux.org"}
	} (1..$limit);
	$specs[3]->{repository_id} = "sabayon-weekly";
	$specs[5]->{repository_id} = "sabayon-weekly";
	$specs[8]->{repository_id} = "sabayon-weekly";
	$test_n_results->(3, 1, @specs);
};

# extension of the results number test
subtest "filtering test" => sub {
	plan tests => 50;

	my $c = App::Querypkg::Stub::Fetch->new;
	my @specs = (
		{atom => "ctg/p-1", repository_id => "sabayonlinux.org", arch => "x86"},
		{atom => "ctg/p-2", repository_id => "sabayonlinux.org", arch => "amd64"},
		{atom => "ctg/p-3", repository_id => "sabayon-weekly", arch => "x86"},
		{atom => "ctg/p-4", repository_id => "sabayon-weekly", arch => "amd64"},
		{atom => "ctg/p-5", repository_id => "sabayon-limbo", arch => "x86"},
		{atom => "ctg/p-6", repository_id => "sabayon-limbo", arch => "amd64"},
	);

	my $check_correctness_for_atom = sub {
		my $pkg = shift; # $pkg comes from next_pkg()
		my $atom = $pkg->{atom};
		my $repository = $pkg->{repository};
		my $arch = $pkg->{arch};

		for my $spec (@specs) {
			if ($spec->{atom} eq $atom) {
				is( $spec->{repository_id}, $repository,
					"atom matches repository ($atom, $repository)" );

				is( $spec->{arch}, $arch,
					"atom matches architecture ($atom, $arch)" );
				return
			}
		}
		fail( "Atom $atom unmatched - name mangled by API?" );
	};

	my $cnt;
	gen_json(@specs);
	$c->make_URI( "whatever" );

	my %repository_mapping = (
		sl    => "sabayonlinux.org",
		we    => "sabayon-weekly",
		limbo => "sabayon-limbo"
	);

	for my $arch (qw(x86 amd64)) {
		for my $repo (qw(sl we limbo all)) {
			$c->set_req_params( arch => $arch, repo => $repo );
			$c->get_data;
			my @pkg_data = ();

			while (my $pkg = $c->next_pkg) {
				push @pkg_data, $pkg;
			}

			my $expected_n_of_results = $repo eq "all" ? 3 : 1;
			is( scalar @pkg_data, $expected_n_of_results,
				"number of results is $expected_n_of_results ($arch, $repo)");

			for my $pkg (@pkg_data) {
				# check if there are no "unmatched" results
				is( $pkg->{arch}, $arch, "arch ok ($arch, $pkg->{atom})" );
				if( $repo ne "all" ) {
					is( $pkg->{repository}, $repository_mapping{$repo},
						"repository ok ($repo, $pkg->{atom})" );
				}

				# Does the data match the package, as compared to @specs?
				$check_correctness_for_atom->( $pkg );
			}
		}
	}
};
