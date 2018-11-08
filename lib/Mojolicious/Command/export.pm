package Mojolicious::Command::export;
our $VERSION = '0.002';
# ABSTRACT: Export a Mojolicious website to static files

=head1 SYNOPSIS

  Usage: APPLICATION export [OPTIONS] [PAGES]

    ./myapp.pl export
    ./myapp.pl export /perldoc --to /var/www/html
    ./myapp.pl export /perldoc --base /url

  Options:
    -h, --help        Show this summary of available options
        --to          Path to store the static pages. Defaults to '.'.
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
            # Configure the default paths to export
            paths => [ '/', '/hidden' ],
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
        base => $config->{base} // '',
    );
    getopt( \@args, \%opt,
        'to=s',
        'base=s',
        'quiet|q' => sub { $self->quiet( 1 ) },
    );

    if ( $opt{base} =~ m{^[^/]} ) {
        $opt{base} = '/' . $opt{base};
    }

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

        my $content = $tx->res->body;
        if ( $type and $type =~ m{^text/html} and my $dom = $res->dom ) {
            my $dir = path( $page )->dirname;
            for my $attr ( qw( href src ) ) {
                for my $el ( $dom->find( "[$attr]" )->each ) {
                    my $url = $el->attr( $attr );

                    # Don't analyze full URLs
                    next if $url =~ m{^(?:[a-zA-Z]+:)?//};

                    # Fix relative paths
                    my $path = $url =~ m{^/} ? $url : $dir->child( $url )."";
                    if ( !$exported{ $path } ) { # Prune duplicates
                        push @pages, $path;
                    }

                    # Rewrite absolute paths
                    if ( $opt{base} && $url =~ m{^/} ) {
                        my $base_url = $url eq '/' ? $opt{base} : $opt{base} . $url;
                        $el->attr( $attr => $base_url );
                    }
                }
            }
            $content = $dom;
        }

        my $to = $root->child( $page );
        if ( $to !~ m{[.][^/.]+$} ) {
            $to = $to->child( 'index.html' );
        }
        $self->write_file( $to, $content );
    }
}

1;

