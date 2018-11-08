package Mojolicious::Command::export;
our $VERSION = '0.002';
# ABSTRACT: Export a Mojolicious website to static files

=head1 SYNOPSIS

  Usage: APPLICATION export [OPTIONS] [PAGES]

    ./myapp.pl export
    ./myapp.pl export /perldoc --to /var/www/html

  Options:
    -h, --help        Show this summary of available options
        --to          Path to store the static pages. Defaults to '.'.
    -q, --quiet       Silence report of dirs/files modified

=head1 DESCRIPTION

Export a Mojolicious webapp to static files.

=head2 Configuration

Default values for the command's options can be specified in the
configuration using one of Mojolicious's configuration plugins.

    # myapp.conf
    {
        export => {
            # Configure the default paths to export
            paths => [ '/', '/hidden' ],
            # The directory to export to
            to => '/var/www/html',
        }
    }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Commands>

=cut

use Mojo::Base 'Mojolicious::Command';
use Mojo::File qw( path );
use Mojo::Util qw( getopt );

has description => 'Export site to static files';
has usage => sub { shift->extract_usage };

sub run {
    my ( $self, @args ) = @_;
    my $app = $self->app;
    my $config = $app->can( 'config' ) ? $app->config->{export} : {};
    my %opt = (
        to => $config->{to} // '.',
    );
    getopt( \@args, \%opt,
        'to=s',
        'quiet|q' => sub { $self->quiet( 1 ) },
    );

    my $root = path( $opt{ to } );
    my @pages
        = @args ? map { m{^/} ? $_ : "/$_" } @args
        : $config->{pages} ? @{ $config->{pages} }
        : ( '/' );

    my $ua = Mojo::UserAgent->new;
    $ua->server->app( $self->app );

    my %exported;
    while ( my $page = shift @pages ) {
        next if $exported{ $page };
        $exported{ $page }++;
        my $tx = $ua->get( $page );
        my $res = $tx->res;
        my $type = $res->headers->content_type;
        if ( $type and $type =~ m{^text/html} and my $dom = $res->dom ) {
            my $dir = path( $page )->dirname;
            push @pages,
                grep { !$exported{ $_ } } # Prune duplicates
                map { m{^/} ? $_ : $dir->child( $_ )."" } # Fix relative URLs
                grep { !m{^(?:[a-zA-Z]+:)?//} } # Not full URLs
                $dom->find( '[href]' )->map( attr => 'href' )->each,
                $dom->find( '[src]' )->map( attr => 'src' )->each,
                ;
        }

        my $to = $root->child( $page );
        if ( $to !~ m{[.][^/.]+$} ) {
            $to = $to->child( 'index.html' );
        }
        $self->write_file( $to, $tx->res->body )
    }
}

1;

