package Mojolicious::Plugin::Export;
our $VERSION = '0.005';
# ABSTRACT: Export a Mojolicious website to static files

=head1 SYNOPSIS

    use Mojolicious::Lite;
    get '/' => 'index';
    get '/secret' => 'secret';
    plugin Export => {
        paths => [qw( / /secret )],
    };
    app->start;

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

=head1 HELPERS

=head2 export

The C<export> helper returns the L<Mojolicious::Plugin::Export> object.

=head1 SEE ALSO

L<Mojolicious::Command::export>, L<Mojolicious::Plugin>

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::File qw( path );
use Mojo::Util qw( encode decode );

=attr pages

The pages to export by default. This can be overridden by the arguments to
L</export>.

    # Add pages to export by default
    push @{ $app->export->pages }, '/blog';

=cut

has pages => sub { [] };

=attr to

The path to export to by default.

=cut

has to => '.';

=attr base

The base URL, if URLs need to be rewritten.

=cut

has base => '';

=attr quiet

If true, will not report every action taken by the plugin. Defaults to true.

=cut

has quiet => 1;

has _app =>;

sub register {
    my ( $self, $app, $plugin_conf ) = @_;
    $self->_app( $app );
    $app->helper( export => sub { $self } );

    # Config file overrides plugin config
    my $config = $app->can( 'config' ) ? $app->config->{export} : {};
    for my $key ( keys %$config ) {
        $self->$key( $config->{ $key } // $plugin_conf->{ $key } );
    }

    return $self;
}

=method export

    app->export->export( $override );

Export the site. C<$override> is a hash reference to override the object
attributes (keys are attribute names, values are the overridden value).

=cut

sub export {
    my ( $self, $opt ) = @_;
    for my $key ( qw( pages to base quiet ) ) {
        $opt->{ $key } //= $self->$key;
    }

    if ( $opt->{base} && $opt->{base} =~ m{^[^/]} ) {
        $opt->{base} = '/' . $opt->{base};
    }

    my $root = path( $opt->{ to } );
    my @pages
        = @{ $opt->{pages} } ? map { m{^/} ? $_ : "/$_" } @{ $opt->{pages} }
        : ( '/' );

    my $ua = Mojo::UserAgent->new;
    $ua->server->app( $self->_app );

    # A hash of path => knowledge about the path
    #   link_from => a hash of path -> array of DOM elements linking to original path
    #   res => The response from the request for this page
    #   redirect_to => The redirect location, if it was a redirect
    my %history;

    while ( my $page = shift @pages ) {
        next if $history{ $page }{ res };
        my $tx = $ua->get( $page );
        my $res = $history{ $page }{ res } = $tx->res;

        # Do not try to write error messages
        if ( $res->is_error ) {
            if ( !$opt->{quiet} ) {
                say sprintf "  [ERROR] %s - %s %s",
                    $page, $res->code, $res->message;
            }
            next;
        }

        # Rewrite links to redirects
        if ( $res->is_redirect ) {
            my $loc = $history{ $page }{ redirect_to } = $res->headers->location;
            say "  [redir] Found redirect. Fixing links to this page"
                unless $opt->{quiet};
            for my $link_from ( keys %{ $history{ $page }{ link_from } } ) {
                for my $el ( @{ $history{ $page }{ link_from }{ $link_from } } ) {
                    $el->attr( href => $loc );
                }
                my $content = $history{ $link_from }{ res }->dom;
                $self->_write( $root, $link_from, $content, $opt->{quiet} );
            }
            next;
        }

        my $type = $res->headers->content_type;
        my $content = $tx->res->body;
        if ( $type and $type =~ m{^text/html} and my $dom = $res->dom ) {
            my $dir = path( $page )->dirname;
            for my $attr ( qw( href src ) ) {
                for my $el ( $dom->find( "[$attr]" )->each ) {
                    my $url = $el->attr( $attr );

                    # Don't analyze full URLs
                    next if $url =~ m{^(?:[a-zA-Z]+:)?//};
                    # Don't analyze in-page fragments
                    next if $url =~ m{^#};

                    # Fix relative paths
                    my $path = $url =~ m{^/} ? $url : $dir->child( $url )."";
                    # Remove fragment
                    $path =~ s/#.+//;

                    if ( my $loc = $history{ $path }{ redirect_to } ) {
                        $el->attr( $attr => $loc );
                        next;
                    }
                    else {
                        push @{ $history{ $path }{ link_from }{ $page } }, $el;
                    }

                    if ( !$history{ $path }{ res } ) {
                        push @pages, $path;
                    }

                    # Rewrite absolute paths
                    if ( $opt->{base} && $url =~ m{^/} ) {
                        my $base_url = $url eq '/' ? $opt->{base} : $opt->{base} . $url;
                        $el->attr( $attr => $base_url );
                    }
                }
            }
            $content = $dom;
        }

        $self->_write( $root, $page, $content, $opt->{quiet} );
    }
}

sub _write {
    my ( $self, $root, $page, $content, $quiet ) = @_;
    if ( ref $content eq 'Mojo::DOM' ) {
        # Mojolicious automatically decodes using the response content
        # type, so all we need to do is encode it into the file content
        # type that we want
        # TODO: Allow configuring the destination encoding
        # TODO: Ensure all text/* MIME types use the destination
        # encoding
        $content = encode 'utf8', $content;
    }
    my $to = $root->child( $page );
    if ( $to !~ m{[.][^/.]+$} ) {
        $to = $to->child( 'index.html' );
    }

    my $dir = $to->dirname;
    if ( !-d $dir ) {
        $dir->make_path;
        say "  [mkdir] $dir" unless $quiet;
    }
    else {
        say "  [exist] $dir" unless $quiet;
    }

    say "  [write] $to" unless $quiet;
    $to->spurt( $content );
}

1;
