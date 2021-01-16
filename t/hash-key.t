use strict;
use warnings;

use lib 't/lib';

use App::perlimports ();
use TestHelper qw( file2includes source2pi );
use Test::More;

my @includes = file2includes('test-data/http-status.pl');

my $e = source2pi(
    'test-data/http-status.pl', undef,
    { include => $includes[2] }
);

is(
    $e->formatted_ppi_statement,
    q{use HTTP::Status qw( is_info );},
    'does not think hash key is a function'
);

done_testing;
