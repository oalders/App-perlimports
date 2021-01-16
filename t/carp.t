use strict;
use warnings;

use lib 't/lib';

use App::perlimports           ();
use App::perlimports::Document ();
use Test::More import => [ 'done_testing', 'is', 'is_deeply', 'subtest' ];
use TestHelper qw( source2pi );

subtest 'verbose' => sub {
    my $source_text = 'use Carp qw( croak verbose );';
    my $e           = source2pi( 'test-data/carp.pl', $source_text );

    is(
        $e->formatted_ppi_statement,
        $source_text,
        'verbose is preserved'
    );

    is_deeply(
        $e->_original_imports,
        [ 'croak', 'verbose' ],
        'original imports'
    );
};

subtest 'no verbose' => sub {
    my $source_text = 'use Carp qw( croak );';
    my $e           = source2pi( 'test-data/carp.pl', $source_text );

    is(
        $e->formatted_ppi_statement,
        $source_text,
        'verbose is not inserted'
    );

    is_deeply(
        $e->_original_imports,
        ['croak'],
        'original imports'
    );
};

subtest 'no imports' => sub {
    my $source_text = 'use Carp ();';

    my $e = source2pi( 'test-data/carp.pl', $source_text );

    is(
        $e->formatted_ppi_statement,
        'use Carp qw( croak );',
        'verbose is not inserted'
    );

    is_deeply(
        $e->_original_imports,
        [],
        'original imports'
    );
};

done_testing();
