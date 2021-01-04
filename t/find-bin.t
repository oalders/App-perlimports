use strict;
use warnings;

use App::perlimports ();
use Test::More import => [ 'done_testing', 'is', 'ok' ];

# This test demonstrates that we can't handle FindBin
my $e = App::perlimports->new(
    filename    => 'test-data/find-bin.pl',
    source_text => 'use FindBin qw( $Bin );',
);
is(
    $e->_module_name(), 'FindBin',
    '_module_name'
);

ok( $e->_is_ignored, 'noop' );
is(
    $e->formatted_ppi_statement,
    q{use FindBin qw( $Bin );},
    'formatted_ppi_statement'
);

done_testing();
