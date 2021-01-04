package App::perlimports;

use Moo;

use Data::Dumper qw( Dumper );
use Data::Printer;
use List::AllUtils qw( any uniq );
use Module::Runtime qw( module_notional_filename require_module );
use Module::Util qw( find_installed );
use MooX::HandlesVia;
use Path::Tiny qw( path );
use Perl::Critic::Utils 1.138 qw( is_function_call );
use Perl::Tidy 20201207 qw( perltidy );
use PPI::Document 1.270 ();
use Ref::Util qw( is_plain_hashref );
use Try::Tiny qw( catch try );
use Types::Standard qw(ArrayRef Bool HashRef InstanceOf Maybe Str);

has _combined_exports => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_combined_exports',
);

has errors => (
    is          => 'rw',
    isa         => ArrayRef,
    handles_via => 'Array',
    handles     => {
        _add_error => 'push',
        has_errors => 'count',
    },
    init_arg => undef,
    default  => sub { [] },
);

has _export => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_export',
);

has _export_ok => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_export_ok',
);

has _filename => (
    is       => 'ro',
    isa      => Str,
    init_arg => 'filename',
    required => 1,
);

has formatted_ppi_statement => (
    is      => 'ro',
    isa     => InstanceOf ['PPI::Statement::Include'],
    lazy    => 1,
    builder => '_build_formatted_ppi_statement',
);

has _ignored_modules => (
    is        => 'ro',
    isa       => ArrayRef,
    init_arg  => 'ignored_modules',
    predicate => '_has_ignored_modules',
);

has _imports => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_imports',
);

has _include => (
    is       => 'ro',
    isa      => InstanceOf ['PPI::Statement::Include'],
    init_arg => 'include',
    required => 1,
);

has _is_ignored => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => '_build_is_ignored',
);

has _is_moose_type_library => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->_has_moose_types && defined $self->_moose_types;
    },
);

has _isa_test_builder_module => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => '_build_isa_test_builder_module',
);

has _libs => (
    is       => 'ro',
    isa      => ArrayRef,
    init_arg => 'libs',
    lazy     => 1,
    default  => sub { [ 'lib', 't/lib' ] },
);

has _module_name => (
    is      => 'ro',
    isa     => Maybe [Str],
    lazy    => 1,
    default => sub { shift->_include->module },
);

# If this attribute is undef, it means we tried to look for Moose types but
# this probably is not a Moose type library.
has _moose_types => (
    is        => 'ro',
    isa       => Maybe [ArrayRef],
    predicate => '_has_moose_types',
    lazy      => 1,
    builder   => '_build_moose_types',
);

has _never_exports => (
    is      => 'ro',
    isa     => HashRef,
    lazy    => 1,
    builder => '_build_never_exports',
);

# Abuse attributes to ensure this only happens once
has _maybe_require_and_import_module => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => '_build_maybe_require_and_import_module',
);

has _original_imports => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_original_imports',
);

has _uses_sub_exporter => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    builder => '_build_uses_sub_exporter',
);

has _will_never_export => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    default => sub {
        my $self = shift;
        return exists $self->_never_exports->{ $self->_module_name };
    },
);

around BUILDARGS => sub {
    my ( $orig, $class, @args ) = @_;

    my %args = @args;
    if ( my $source = delete $args{source_text} ) {
        my $doc = PPI::Document->new( \$source );
        my $includes
            = $doc->find( sub { $_[1]->isa('PPI::Statement::Include'); } );
        $args{include} = $includes->[0]->clone;
    }

    return $class->$orig(%args);
};

sub _build_maybe_require_and_import_module {
    my $self   = shift;
    my $module = $self->_module_name;
    return 0 if $self->_will_never_export;

    my $error = 0;

    return 0 unless $self->_maybe_require_module($module);

    # This is helpful for (at least) POSIX and Test::Most
    try {
        $module->import;
    }
    catch {
        push @{ $self->errors }, $_;
    };

    return 1;
}

sub _build_combined_exports {
    my $self   = shift;
    my $module = $self->_module_name;

    return [] if $self->_will_never_export;

    my @exports = uniq( @{ $self->_export }, @{ $self->_export_ok } );

    # If we have undef for Moose types, we don't want to return that in this
    # builder, since this attribute cannot be undef.
    return
          @exports            ? \@exports
        : $self->_moose_types ? $self->_moose_types
        :                       [];
}

sub _build_export {
    my $self = shift;

    return [] if $self->_will_never_export;

    $self->_maybe_require_and_import_module;

## no critic (TestingAndDebugging::ProhibitNoStrict)
    no strict 'refs';
    my @exports = @{ $self->_module_name . '::EXPORT' };
    use strict;
## use critic

    return @exports ? \@exports : [];
}

sub _build_export_ok {
    my $self = shift;

    return [] if $self->_will_never_export;

    $self->_maybe_require_and_import_module;

## no critic (TestingAndDebugging::ProhibitNoStrict)
    no strict 'refs';
    my @exports = @{ $self->_module_name . '::EXPORT_OK' };
    use strict;
## use critic

    return @exports ? \@exports : [];
}

# Moose Type library? And yes, private method bad.
sub _build_moose_types {
    my $self = shift;

    my @exports;

    # Don't wrap this require as we really do want to die if this module cannot
    # be found.
    require_module('Class::Inspector');

    if (
        any { $_ eq 'MooseX::Types::Combine::_provided_types' }
        @{ Class::Inspector->methods(
                $self->_module_name, 'full', 'private'
                )
                || []
        }
    ) {
        my %types = $self->_module_name->_provided_types;
        @exports = map { $_, 'is_' . $_, 'to_' . $_ } keys %types;
    }
    return @exports ? \@exports : undef;
}

sub _build_isa_test_builder_module {
    my $self = shift;
    $self->_combined_exports;    # ensure module has already been required

## no critic (TestingAndDebugging::ProhibitNoStrict)
    no strict 'refs';
    my $isa_test_builder = any { $_ eq 'Test::Builder::Module' }
    @{ $self->_module_name . '::ISA' };
    use strict;
## use critic

    return $isa_test_builder ? 1 : 0;
}

sub _build_imports {
    my $self = shift;

    my $content = path( $self->_filename )->slurp;
    my $doc     = PPI::Document->new( \$content );

    my %exports = map { $_ => 1 } @{ $self->_combined_exports };

    # This is not a real symbol, so we should never be looking for it to appear
    # in the code.
    delete $exports{verbose} if $self->_module_name eq 'Carp';

    # Stolen from Perl::Critic::Policy::TooMuchCode::ProhibitUnfoundImport
    my %found;
    for my $word (
        @{
            $doc->find(
                sub {
                    $_[1]->isa('PPI::Token::Word')
                        || $_[1]->isa('PPI::Token::Symbol')
                        || $_[1]->isa('PPI::Token::Label');
                }
                )
                || []
        }
    ) {
        my $found_import;

        # If a module exports %foo and we find $foo{bar}, $word->canonical
        # returns $foo and $word->symbol returns %foo
        if ( $word->isa('PPI::Token::Symbol')
            && exists $exports{ $word->symbol } ) {
            $found_import = $word->symbol;
        }

        elsif (
            exists $exports{"$word"}

            # Maybe a subroutine ref has been exported. For instance,
            # Getopt::Long exports &GetOptions
            || ( is_function_call($word)
                && exists $exports{ '&' . "$word" } )
        ) {
            $found_import = "$word";
        }

        # PPI can think that an imported function in a ternary is a label
        # my $foo = $enabled ? GEOIP_MEMORY_CACHE : 0;
        # The content of the $word will be "GEOIP_MEMORY_CACHE :"
        elsif ( $word->isa('PPI::Token::Label') ) {
            if ( $word->content =~ m{^(\w+)} ) {
                my $label = $1;
                if ( exists $exports{$label} ) {
                    $found_import = $label;
                    $found{$label}++;
                }
            }
        }

        # If a Moose type has been imported but an exported type check or
        # coercion is found, make sure we still use the actual type as the
        # import name. So, is_HashRef or to_HashRef should still show up as
        # HashRef in the import list. There could be cases where the type is
        # imported just to use a coercion or type check. In that case we won't
        # find the actual type name in the code.
        if (   $found_import
            && $self->_is_moose_type_library
            && $found_import =~ m{^(is_|to_)} ) {
            $found_import = substr( $found_import, 3 );
        }

        $found{$found_import}++ if $found_import;
    }

    # Carp exports verbose, which is a symbol which doesn't actually exist.
    # It's basically a flag, so if it's in the import, we'll just preserve it.
    if (
        $self->_module_name eq 'Carp' && (
            any { $_ eq 'verbose' }
            @{ $self->_original_imports }
        )
    ) {
        $found{verbose} = 1;
    }

    my @found = sort { "\L$a" cmp "\L$b" } keys %found;
    return \@found;
}

sub _build_original_imports {
    my $self = shift;

    # Stolen from Perl::Critic::Policy::TooMuchCode::ProhibitUnusedImport
    my $expr_qw
        = $self->_include->find(
        sub { $_[1]->isa('PPI::Token::QuoteLike::Words'); } )
        or next;

    my @imports;
    if ( @$expr_qw == 1 ) {
        my $expr  = $expr_qw->[0];
        my @words = $expr_qw->[0]->literal;
        for my $w (@words) {
            next if $w =~ /\A [:\-\+]/x;
            push @imports, $w;
        }
    }

    return \@imports;
}

sub _build_is_ignored {
    my $self = shift;

    # Ignore undef, "require" and "no"
    if ( !$self->_include->type || $self->_include->type ne 'use' ) {
        return 1;
    }

    # Is it a pragma?
    return 1 if $self->_include->pragma;

    # Is this a dependency on a version of Perl?
    # use 5.006;
    # require 5.006;
    return 1 if $self->_include->version;

    # We know what FindBin exports, but we need to be smarter about checking
    # for exported variables inside quotes in order for this to be correct.

    my %noop = (
        'FindBin'                => 1,
        'namespace::autoclean'   => 1,
        'Test::Needs'            => 1,
        'Test::RequiresInternet' => 1,
        'Types::Standard'        => 1,
    );

    if ( $self->_has_ignored_modules ) {
        for my $name ( @{ $self->_ignored_modules } ) {
            $noop{$name} = 1;
        }
    }

    return 1 if exists $noop{ $self->_module_name };

    if ( $self->_will_never_export
        || @{ $self->_imports } ) {
        return 0;
    }

    return 1 if $self->_uses_sub_exporter;

    # This should catch Moose classes
    if ( $self->_maybe_require_module('Moose::Util')
        && Moose::Util::find_meta( $self->_module_name ) ) {
        return 1;
    }

    # This should catch Moo classes
    if ( $self->_maybe_require_module('Class::Inspector') ) {
        return 1
            if any { $_ eq 'Moo::is_class' }
        @{ Class::Inspector->methods(
                $self->_module_name, 'full', 'public'
                )
                || []
        };
    }

    return 0;
}

# Returns a HashRef of modules which will always be converted to avoid imports.
# This is mostly for speed and a matter of convenience so that we don't have to
# examine modules (like strictly Object Oriented modules) which we know will
# not have anything to export.

sub _build_never_exports {
    my $self = shift;
    return {
        'App::perlimports' => 1,
        'LWP::UserAgent'   => 1,
        'WWW::Mechanize'   => 1,
    };
}

sub _build_formatted_ppi_statement {
    my $self = shift;

    # Cases where we don't want to rewrite the include because we can't be
    # confident that we're doing the right thing.
    if (
        $self->_is_ignored
        || (   !@{ $self->_combined_exports }
            && !$self->_will_never_export )
    ) {
        return $self->_include;
    }

    # In this case we either have a module which can never export or a module
    # which can export but doesn't appear to. In both cases we'll want to
    # rewrite with an empty list of imports.
    if ( $self->_will_never_export
        || !@{ $self->_imports } ) {
        return $self->_new_include(
            sprintf(
                'use %s %s();', $self->_module_name,
                $self->_include->module_version
                ? $self->_include->module_version . q{ }
                : q{}
            )
        );
    }

    my $statement;

    my @args = $self->_include->arguments;

    # Don't touch a do { } block.
    if ( $self->_isa_test_builder_module && @args && $args[0] eq 'do' ) {
        return $self->_include;
    }

    # Do some contortions to turn PPI objects back into a data structure so
    # that we can add or replace an import hash key and then end up with a new
    # list which is sorted on hash keys. This makes the assumption that the
    # same key won't get passed twice. This is pretty gross, but I was too lazy
    # to try to figure out how to do this with PPI and I think it should
    # *mostly* work. I don't like the formatting that Data::Dumper comes up
    # with, so we'll run it through perltidy.

    if (   $self->_isa_test_builder_module
        && @args ) {
        my $all;

        if ( $args[0]->isa('PPI::Token::Word') ) {
            $all = join q{ }, map { "$_" } @args;
        }

        elsif ($args[0]->isa('PPI::Structure::List')
            && $args[0]->braces eq '()' ) {
            for my $child ( $args[0]->children ) {
                $all .= "$child";
            }
        }

        ## no critic (BuiltinFunctions::ProhibitStringyEval)
        my $args;
        my $error;
        try {
            $args = eval( '{' . $all . '}' );
        }
        catch {
            $self->_add_error($_);
            $error = 1;
        };
        ## use critic

        if ( !$error && !is_plain_hashref($args) ) {
            $self->_add_error( 'Not a hashref: ' . np($args) );
            $error = 1;
        }

        # Ignore this line if we can't parse it. This will happen if the arg to
        # test is a do block, for example.
        return $self->_include if $error;

        local $Data::Dumper::Terse         = 1;
        local $Data::Dumper::Indent        = 0;
        local $Data::Dumper::Sortkeys      = 1;
        local $Data::Dumper::Quotekeys     = 0;
        local $Data::Dumper::Useqq         = 0;
        local $Data::Dumper::Trailingcomma = 1;
        local $Data::Dumper::Deparse       = 1;

        $args->{import} = $self->_imports;

        my $dumped = Dumper($args);
        my $formatted;
        if ( $dumped =~ m/^{(.*)}$/ ) {
            $formatted = $1;
        }

        $statement = sprintf(
            keys %$args > 1 ? 'use %s%s( %s );' : 'use %s%s %s;',
            $self->_module_name,
            $self->_include->module_version
            ? q{ } . $self->_include->module_version . q{ }
            : q{ },
            $formatted
        );

        perltidy(
            argv        => '-npro',
            source      => \$statement,
            destination => \$statement
        );
    }

    else {
        my $template
            = $self->_isa_test_builder_module
            ? 'use %s%s import => [ qw( %s ) ];'
            : 'use %s%s qw( %s );';

        $statement = sprintf(
            $template, $self->_module_name,
            $self->_include->module_version
            ? q{ } . $self->_include->module_version
            : q{}, join q{ },
            @{ $self->_imports }
        );
    }

    # Don't deal with Test::Builder classes here to keep is simple for now
    if ( length($statement) > 78 && !$self->_isa_test_builder_module ) {
        $statement = sprintf( "use %s qw(\n", $self->_module_name );
        for ( @{ $self->_imports } ) {
            $statement .= "    $_\n";
        }
        $statement .= ");";
    }

    return $self->_new_include($statement);
}

sub _new_include {
    my $self      = shift;
    my $statement = shift;
    my $doc       = PPI::Document->new( \$statement );
    my $includes
        = $doc->find( sub { $_[1]->isa('PPI::Statement::Include'); } );
    return $includes->[0]->clone;
}

# Stolen from Open::This
sub _maybe_find_local_module {
    my $self          = shift;
    my $module        = $self->_module_name;
    my $possible_name = module_notional_filename($module);

    for my $dir ( @{ $self->_libs } ) {
        my $path = path( $dir, $possible_name );
        if ( $path->is_file ) {
            return "$path";
        }
    }
    return undef;
}

# Stolen from Open::This
sub _maybe_find_installed_module {
    my $self = shift;

    # This is a loadable module.  Have this come after the local module checks
    # so that we don't default to installed modules.
    return find_installed( $self->_module_name );
}

sub _build_uses_sub_exporter {
    my $self     = shift;
    my $module   = $self->_module_name;
    my $filename = $self->_maybe_find_local_module
        || $self->_maybe_find_installed_module;

    if ( !$filename ) {
        $self->_add_error(
            "Cannot find $module when testing for Sub::Exporter");
        return;
    }

    my $content = path($filename)->slurp;
    my $doc     = PPI::Document->new( \$content );

    # Stolen from Perl::Critic::Policy::TooMuchCode::ProhibitUnfoundImport
    my $include_statements = $doc->find(
        sub {
            $_[1]->isa('PPI::Statement::Include') && !$_[1]->pragma;
        }
    ) || [];
    for my $st (@$include_statements) {
        next if $st->schild(0) eq 'no';

        my $included_module = $st->schild(1);
        if ( $included_module eq 'Sub::Exporter' ) {
            return 1;
        }
    }
    return 0;
}

sub _maybe_require_module {
    my $self              = shift;
    my $module_to_require = shift;

    my $success;
    try {
        require_module($module_to_require);
        $success = 1;
    }
    catch {
        $self->_add_error("$module_to_require error. $_");
    };

    return $success;
}

1;

# ABSTRACT: Make implicit imports explicit

=pod

=head1 DESCRIPTION

This distribution provides the L<perlimports> binary, which aims to automate
the cleanup and maintenance of Perl import statements.

=head1 SYNOPSIS

Update a file in place. (Make sure you can revert the file if you need to.)

    perlimports --filename test-data/foo.pl --inplace-edit

If some of your imported modules are in local directories, you can give some
hints as to where to find them:

    perlimports --filename test-data/foo.pl --inplace-edit --libs t/lib,/some/dir/lib

Redirect output to a new file:

    perlimports --filename test-data/foo.pl > foo.new.pl

=head2 VIM

If you're a C<vim> user, you can pipe your import statements to L<perlimports> directly.

    :vnoremap <silent> im :!perlimports --read-stdin --filename '%:p'<CR>

The above statement will allow you to visually select one or more lines of code
and have them updated in place by L<perlimports>. Once you have selected the
code enter C<im> to have your imports (re)formatted.

=head2 MOTIVATION

Many Perl modules helpfully export functions and variables by default. These
provide handy shortcuts when you're writing a quick or small script, but they
can quickly become a maintenance burden as code grows organically.

=over

=item Problem: Where is this function defined?

You may come across some code like this:

    use strict;
    use warnings;

    use HTTP::Request::Common;
    use LWP::UserAgent;

    my $ua = LWP::UserAgent->new;
    my $req = $ua->request( GET 'https://metacpan.org/' );
    print $req->content;

Where does C<GET> come from? If you're not familiar with
L<HTTP::Request::Common>, you may not realize that the statement C<use
HTTP::Request::Common> has imported the functions C<GET>, C<HEAD>, C<PUT>,
C<PATCH>, C<POST> and C<OPTIONS> into to this block of code.

=item Solution:

Import all needed functions explicitly.

    use strict;
    use warnings;

    use HTTP::Request::Common qw( GET );
    use LWP::UserAgent ();

    my $ua = LWP::UserAgent->new;
    my $req = $ua->request( GET 'https://metacpan.org/' );
    print $req->content;

The code above makes it immediately obvious where C<GET> originates, which
makes it easier for us to look up its documentation. It has the added bonus of
also not importing C<HEAD>, C<PUT> or any of the other functions which
L<HTTP::Request::Common> exports by default. So, those functions cannot
unwittingly be used later in the code. This makes for more understandable code
for present day you, future you and any others tasked with reading your code at
some future point.

Keep in mind that this simple act can save much time for developers who are not
intimately familiar with Perl and the default exports of many CPAN modules.

=item Problem: Are we using all of these imports?

Imagine the following import statement

    use HTTP::Status qw(
        is_cacheable_by_default
        is_client_error
        is_error
        is_info
        is_redirect
        is_server_error
        is_success
        status_message
    );

followed by 3,000 lines of code. How do you know if all of these functions are
being used? You can grep all of these function names manually or you can remove
them by trial and error to see what breaks. This is a doable solution, but it
does not scale well to scripts and modules with many imports or to large code
bases with many imports. Having an unmaintained list of imports is preferable
to implicit imports, but it would be helpful to automate maintaining this list.

=item Solution: remove unused airports

L<perlimports> can, in many situations, clean up your import statements and
automate this maintenance burden away. This makes it easier for you to write
clean code, which is easier to understand.

=item Problem: Are we using all of these modules?

In cases where code is implicitly importing from modules or where explicit
imports are not being curated, it can be hard to discover which modules are no
longer being used in a script, module or even a code base. Removing unused
modules from code can lead to gains in performance and decrease in consumption
of resources. Removing entire modules from your code base can decrease the
number of dependencies which you need to manage and decrease friction in your
your deployment process.

=item Solution

Actively cleaning up your imports can make this much easier to manage.

=item Problem: Enforcing consistent style

Having a messy list of module imports makes your code harder to read. Imagine
this:

    use Cpanel::JSON::XS;
    use Database::Migrator::Types qw( HashRef ArrayRef Object Str Bool Maybe CodeRef FileHandle RegexpRef );
    use List::AllUtils qw( uniq any );
    use LWP::UserAgent    q{};
    use Try::Tiny qw/ catch     try /;
    use WWW::Mechanize  q<>;

=item Solution:

L<perlimports> turns the above list into:

    use Cpanel::JSON::XS ();
    use Database::Migrator::Types qw(
        ArrayRef
        Bool
        CodeRef
        FileHandle
        HashRef
        Maybe
        Object
        RegexpRef
        Str
    );
    use List::AllUtils qw( any uniq );
    use LWP::UserAgent ();
    use Try::Tiny qw( catch try);
    use WWW::Mechanize ();

Where possible, L<perlimports> will enforce a consistent style of parentheses
and will also sort your imports and break up long lines.

=back

=head2 formatted_ppi_statement

Returns an L<PPI::Statement::Include> object. This can be stringified into an
import statement or used to replace an existing L<PPI::Statement::Include>.

=head1 CAVEATS

Does not work with modules using L<Sub::Exporter>.

=head1 SEE ALSO

L<Perl::Critic::Policy::TooMuchCode::ProhibitUnusedImport>,
L<Perl::Critic::Policy::TooMuchCode::ProhibitUnusedInclude> and
L<Perl::Critic::Policy::TooMuchCode::ProhibitUnusedConstant>

=cut
