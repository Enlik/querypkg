use strict;
use warnings;

# a simple interface to packages.sabayon.org - tests
# (C) 2011-2012, 2014 by Enlik <poczta-sn at gazeta . pl>
# license: MIT

use Test::More tests => 36;
BEGIN { use_ok('App::Querypkg') };

#########################

# Stubs and whatnot.

{
	package App::Querypkg::Stub::CompTest;
	use base 'App::Querypkg';
	our $order;

	sub get_req_param {
		die "order is unknown" unless defined $order;
		$order
	}
}

# Tests for features that don't require network access.

use App::Querypkg;
my $c = App::Querypkg->new;

ok( $c->isa('App::Querypkg'), "ISA test" );

# Check if default arch is the expected one, even though it's not important.
is( $c->get_req_param('arch'), 'amd64', "default arch value" );

subtest "set/get request parameters test" => sub {
	plan tests => 11;
	for my $param (qw(x86 amd64)) {
		$c->set_req_params(arch => $param);
		is( $c->get_req_param('arch'), $param, "arch value ($param)" );
	}

	for my $param (qw(pkg use set)) {
		$c->set_req_params(type => $param);
		is( $c->get_req_param('type'), $param, "type value ($param)" );
	}

	for my $param (qw(alph vote size)) {
		$c->set_req_params(order => $param);
		is( $c->get_req_param('order'), $param, "order value ($param)" );
	}

	for my $param (qw(sl p pg)) {
		$c->set_req_params(repo => $param);
		is( $c->get_req_param('repo'), $param, "repo value ($param)" );
	}
};

subtest "params defined with one sub call" => sub {
	plan tests => 4;
	$c->set_req_params(
		arch => 'x86', type => 'match', order => 'downloads', repo => 'psl');
	is( $c->get_req_param('arch'), 'x86', "arch value" );
	is( $c->get_req_param('type'), 'match', "type value" );
	is( $c->get_req_param('order'), 'downloads', "order value" );
	is( $c->get_req_param('repo'), 'psl', "repo value" );
};

ok( sub {
		eval { $c->set_req_params(archxyz => 'x86'); }; $@
	}->(),
	"exception on wrong parameter (set)"
);

ok( sub {
		eval { $c->set_req_params(arch => 'oops'); }; $@
	}->(),
	"exception on wrong parameter's value (set)"
);

ok( sub {
		eval { $c->get_req_param(archxyz => 'x86'); }; $@
	}->(),
	"exception on wrong parameter (get)"
);

my $ret = $c->get_data();
ok( !$ret, "get_data() with no URI return value");
is( $c->geterr(), "URI hasn't been defined.", "get_data() with no URI error");

ok( sub {
		eval { $c->next_pkg(); }; $@
	}->(),
	"next_pkg() called too early"
);

ok( sub {
		eval { $c->limit_reached(); }; $@
	}->(),
	"limit_reached() called too early"
);

my $got;
subtest "make_URI() related tests" => sub {
	plan tests => 9;
	$c->set_req_params(
		arch => 'x86', type => 'pkg', order => 'downloads', repo => 'p');
	$got = $c->make_URI( "haha" );
	like( $got, qr/\?q=haha&/, "URI: keyword ok" );
	like( $got, qr/&t=pkg&/, "URI: type ok" );
	like( $got, qr/&a=arch&/, "URI: arch ok" );
	like( $got, qr/&o=downloads&/, "URI: order ok" );

	$got = $c->make_URI( '@key' );
	like( $got, qr/\?q=%40key&/, "URI: keyword ok (\@keyword)" );

	$c->set_req_params(type => 'set');
	$got = $c->make_URI( 'haha' );
	like( $got, qr/\?q=\@haha&/, "URI: keyword ok (type set)" );

	$got = $c->make_URI( '@set' );
	like( $got, qr/\?q=\@%40set&/, "URI: keyword ok (type set, \@keyword)" );

	$c->set_req_params(order => 'alph');
	$got = $c->make_URI( 'haha' );
	like( $got, qr/&o=alphabet&/, "URI: order ok (arg. passed)" );

	$c->set_req_params(order => 'date');
	$got = $c->make_URI( 'haha' );
	unlike( $got, qr/[?&]o=/, "URI: order ok (arg. not passed)" );
};

is( $c->get_uri, $got, "URIs are the same");

$c->make_URI( 'x' );
# it can't be a set, package_name_check() tests
$c->set_req_params( type => 'pkg' );
$ret = $c->get_data();
ok( !$ret, "get_data() with too short key (return value check)");
like( $c->geterr(), qr/short/, "get_data() with too short key");

$c->make_URI( 'x' x 65 );
$c->set_req_params( type => 'pkg' );
$ret = $c->get_data();
ok( !$ret, "get_data() with too long key (return value check)");
like( $c->geterr(), qr/long/, "get_data() with too short key");

is ($c->get_keyword(), 'x' x 65, "get_keyword() return value");

is( $c->package_name_check( "bla bla" ), App::Querypkg::PKG_NAME_OK,
	"good package_name_check()");

is( $c->package_name_check( "a", 0 ), App::Querypkg::PKG_NAME_TOO_SHORT,
	"package_name_check() with length = 1, not a set");

is( $c->package_name_check( "a", 1 ), App::Querypkg::PKG_NAME_OK,
	"package_name_check() with length = 1, a set");

$c->set_req_params( type => 'pkg' );
is( $c->package_name_check( "a" ), App::Querypkg::PKG_NAME_TOO_SHORT,
	"package_name_check() with length = 1, not a set (auto)");

$c->set_req_params( type => 'set' );
is( $c->package_name_check( "a" ), App::Querypkg::PKG_NAME_OK,
	"package_name_check() with length = 1, a set (auto)");

# requires network access
#my $ret = $c->get_data($got);
#ok( $ret, "get_data()");

ok( sub {
		eval { $c->comp_size('10','20'); }; $@
	}->(),
	"comp_size: exception with bad size suffix"
);

is( $c->_comp_size('300MB', '300MB'), 0, 'comp_size: =, MB' );
is( $c->_comp_size('3001MB', '300MB'), 1, 'comp_size: >, MB' );
is( $c->_comp_size('300MB', '300GB'), -1, 'comp_size: <, GB/MB' );
is( $c->_comp_size('5GB', '5120MB'), 0, 'comp_size: =, GB/MB' );

subtest "comparator tests" => sub {
	my @order_to_test = qw(alph size vote downloads date);
	plan tests => 1 + @order_to_test * 9;

	my @sorted_atom = qw(that this zet);
	my @sorted_size = qw(300MB 3001MB 5GB);
	my @sorted_vote = qw(1 5 6);
	my @sorted_downloads = (0, 99, 100);
	my @sorted_mtime = qw(1310000000.20 1310000000.21 1320000000.20);

	my @data = map {
		{
			atom => $sorted_atom[$_],
			size => $sorted_size[$_],
			ugc => {
				vote => $sorted_vote[$_],
				downloads => $sorted_downloads[$_]
			},
			mtime => $sorted_mtime[$_]
		}
	} (0..2);

	my $c = App::Querypkg::Stub::CompTest->new;
	ok( $c->isa('App::Querypkg'), "ISA test" );

	my $test_for_order = sub {
		my $order = shift;
		$App::Querypkg::Stub::CompTest::order = $order;

		# NOTE: for all values other than "alph" _comp() returns in reverse
		# order

		my $expectation;

		# test equal
		$expectation = 0;
		for my $i (0..2) {
			is( $c->_comp($data[$i], $data[$i]), $expectation,
				"_comp: $order, =");
		}

		# test lesser than
		$expectation = $order eq "alph" ? -1 : 1;
		for my $i (0..1) {
			for my $j ($i+1..2) {
				is( $c->_comp($data[$i], $data[$j]), $expectation,
					"_comp: $order, <");
			}
		}

		# test greater than
		$expectation = $order eq "alph" ? 1 : -1;
		for my $j (0..1) {
			for my $i ($j+1..2) {
				is( $c->_comp($data[$i], $data[$j]), $expectation,
					"_comp: $order, >");
			}
		}
	};

	for my $order (@order_to_test) {
		$test_for_order->($order);
	}

};

my @h_arch = (
	amd64 => { API => 'amd64', desc => 'amd64' },
	x86 => { API => 'x86', desc => 'x86' }
);

is_deeply([ $c->get_API_array('arch') ], \@h_arch,
	"get_API_array() return value" );

is_deeply([ $c->get_API_array('arch', 1) ], [ qw(amd64 x86) ],
	"get_API_array() return value (opts only)" );

ok( sub {
		eval { $c->get_API_array('haha'); }; $@
	}->(),
	"get_API_array: exception with bad argument"
);

$c->set_req_params( arch => 'amd64', order => 'alph' );
is_deeply( $c->get_API_sel( 'arch' ), { API => 'amd64', desc => 'amd64' },
	"get_API_sel() test" );

is( $c->get_API_sel( 'order' )->{desc}, "alphabetically",
	"get_API_sel()->{field} test" );

is( $c->server_results_limit, 10, "server_results_limit() return value" );
