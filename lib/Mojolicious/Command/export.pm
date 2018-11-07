package Mojolicious::Command::export;
our $VERSION = '0.001';
# ABSTRACT: Export a Mojolicious website to static files

=head1 SYNOPSIS

    ./myapp.pl export [--to <dir>] [<path>...]

=head1 DESCRIPTION

Export a Mojolicious webapp to static files.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Commands>

=cut

use Mojo::Base 'Mojolicious::Command';
use Mojo::File qw( path );
use Getopt::Long qw( GetOptionsFromArray );

sub run {
    my ( $self, @args ) = @_;
    my %opt = (
        to => '.',
    );
    GetOptionsFromArray( \@args, \%opt,
        'to=s',
    );
    my $root = path( $opt{ to } );
    my @pages = @args ? map { m{^/} ? $_ : "/$_" } @args : ( '/' );

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
        $to->dirname->make_path;
        $to->spurt( $tx->res->body );
    }
}

1;

