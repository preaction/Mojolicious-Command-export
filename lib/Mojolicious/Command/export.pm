package Mojolicious::Command::export;
our $VERSION = '0.009';
# ABSTRACT: Export a Mojolicious website to static files

=head1 SYNOPSIS

  Usage: APPLICATION export [OPTIONS] [PAGES]

    ./myapp.pl export
    ./myapp.pl export /perldoc --to /var/www/html
    ./myapp.pl export /perldoc --base /url

  Options:
    -h, --help        Show this summary of available options
        --to <path>   Path to store the static pages. Defaults to '.'.
        --base <url>  Rewrite internal absolute links to prepend base
    -q, --quiet       Silence report of dirs/files modified

=head1 DESCRIPTION

Export a Mojolicious webapp to static files.

=head2 Configuration

Default values for the command's options can be specified in the
configuration using one of Mojolicious's configuration plugins.

    # myapp.conf
    {
        export => {
            # Configure the default pages to export
            pages => [ '/', '/hidden' ],
            # The directory to export to
            to => '/var/www/html',
            # Rewrite URLs to include base directory
            base => '/',
        }
    }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Commands>

=cut

use Mojo::Base 'Mojolicious::Command';
use Mojo::Util qw( getopt );

has description => 'Export site to static files';
has usage => sub { shift->extract_usage };

sub run {
    my ( $self, @args ) = @_;
    my $app = $self->app;
    if ( !$app->can( 'export' ) ) {
        $app->plugin( 'Export' );
    }

    getopt( \@args, \my %opt,
        'to=s',
        'base=s',
        'quiet|q',
    );
    $opt{quiet} //= 0;
    if ( $opt{quiet} ) {
        $self->quiet( 1 );
    }

    if ( @args ) {
        $opt{pages} = \@args;
    }

    $app->export->export( \%opt );
}

1;

