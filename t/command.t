
=head1 DESCRIPTION

This tests the command, configuration, and options.

=head1 SEE ALSO

L<Mojolicious::Command>, L<Mojolicious>

=cut

use Mojo::Base -strict;
use Test::More;
use Mojo::File qw( path tempdir );
use Mojo::DOM;
use Mojolicious::Command::export;
use Mojolicious;

my $app = Mojolicious->new;
unshift @{$app->renderer->classes}, 'main';
unshift @{$app->static->classes}, 'main';
$app->static->warmup;
$app->routes->get( '/' )->name( 'index' );
$app->routes->get( '/docs' )->name( 'docs' );
$app->routes->get( '/docs/more' )->name( 'docs/more' );
$app->routes->get( '/about' )->name( 'about' );

my $cmd = Mojolicious::Command::export->new(
    app => $app,
    quiet => 1,
);

my $dom;
my $home = path;
my $tmp = tempdir;
chdir $tmp;

$cmd->run( '/' ); # Export root
ok -e $tmp->child( 'index.html' ), 'root exists';
$dom = Mojo::DOM->new( $tmp->child( 'index.html' )->slurp );
is $dom->at( 'h1' ), '<h1>Export</h1>', 'root content is correct';

ok -e $tmp->child( 'docs', 'index.html' ), '/docs exists (absolute link)';
$dom = Mojo::DOM->new( $tmp->child( 'docs', 'index.html' )->slurp );
is $dom->at( 'h1' ), '<h1>Docs</h1>', '/docs content is correct';

ok -e $tmp->child( 'docs', 'more', 'index.html' ), '/docs/more exists (relative link)';
$dom = Mojo::DOM->new( $tmp->child( 'docs', 'more', 'index.html' )->slurp );
is $dom->at( 'h1' ), '<h1>More Docs</h1>', '/docs/more content is correct';

ok -e $tmp->child( 'about', 'index.html' ), '/about exists (relative link)';
$dom = Mojo::DOM->new( $tmp->child( 'about', 'index.html' )->slurp );
is $dom->at( 'h1' ), '<h1>About</h1>', '/about content is correct';

ok -e $tmp->child( 'logo-white-2x.png' ), 'image is exported';
ok $tmp->child( 'logo-white-2x.png' )->slurp eq $app->static->file( 'logo-white-2x.png' )->slurp,
    'image content is correct';

ok !-e $tmp->child( 'http' ), 'full urls are not exported';
ok !-e $tmp->child( 'cdnjs.org' ), 'full urls (no scheme) are not exported';

chdir $home;
$tmp = tempdir;
chdir $tmp;
$cmd->run(); # Export root by default
ok -e $tmp->child( 'index.html' ), 'root exists';
ok -e $tmp->child( 'docs', 'index.html' ), '/docs exists (absolute link)';
ok -e $tmp->child( 'docs', 'more', 'index.html' ), '/docs/more exists (relative link)';
ok -e $tmp->child( 'about', 'index.html' ), '/about exists (relative link)';
ok -e $tmp->child( 'logo-white-2x.png' ), 'image is exported';

chdir $home;
$tmp = tempdir;
chdir $tmp;
$cmd->run( '/docs' ); # Only export /docs
ok !-e $tmp->child( 'index.html' ), 'root does not exist';
ok -e $tmp->child( 'docs', 'index.html' ), '/docs exists (page requested)';
ok -e $tmp->child( 'docs', 'more', 'index.html' ), '/docs/more exists (link on page)';
ok !-e $tmp->child( 'about', 'index.html' ), '/about does not exist';
ok !-e $tmp->child( 'logo-white-2x.png' ), 'image is not exported';

# Test URL rewriting
chdir $home;
$tmp = tempdir;
chdir $tmp;
$cmd->run( '--base', '/base', '/' );
ok -e $tmp->child( 'index.html' ), 'root exists';
$dom = Mojo::DOM->new( $tmp->child( 'index.html' )->slurp );
ok $dom->at( 'a[href=/base/docs]' ), 'absolute url (/docs) on / is rewritten';
ok $dom->at( 'a[href=about]' ), 'relative url (about) on / is not rewritten';

ok -e $tmp->child( 'docs', 'index.html' ), '/docs exists (absolute link)';
$dom = Mojo::DOM->new( $tmp->child( 'docs', 'index.html' )->slurp );
ok $dom->at( 'a[href=/base/docs/more]' ), 'absolute url (/docs/more) on /docs is rewritten'
    or diag $dom;

ok -e $tmp->child( 'about', 'index.html' ), '/about exists (relative link)';
$dom = Mojo::DOM->new( $tmp->child( 'about', 'index.html' )->slurp );
ok $dom->at( 'a[href=/base]' ), 'absolute url (/) on /about is rewritten';

ok -e $tmp->child( 'docs', 'more', 'index.html' ), '/docs/more exists (relative link)';
ok -e $tmp->child( 'logo-white-2x.png' ), 'image is exported';

chdir $home;
my $tmp_to = tempdir;
$cmd->run( '--to', $tmp_to );
ok -e $tmp_to->child( 'index.html' ), 'root exists';
ok -e $tmp_to->child( 'docs', 'index.html' ), '/docs exists (absolute link)';
ok -e $tmp_to->child( 'about', 'index.html' ), '/about exists (relative link)';
ok -e $tmp_to->child( 'logo-white-2x.png' ), 'image is exported';

# Test default settings from config
my $config_to = tempdir;
my %config = (
    export => {
        pages => [ '/docs' ],
        to => "$config_to",
        base => '/base',
    },
);
$app->plugin( Config => { default => \%config } );
$cmd->run();
ok !-e $config_to->child( 'index.html' ), 'root does not exist';
ok -e $config_to->child( 'docs', 'index.html' ), '/docs exists (page requested)';
$dom = Mojo::DOM->new( $config_to->child( 'docs', 'index.html' )->slurp );
ok $dom->at( 'a[href=/base/docs/more]' ), 'absolute url is rewritten'
    or diag $dom;
ok -e $config_to->child( 'docs', 'more', 'index.html' ), '/docs/more exists (link on page)';
ok !-e $config_to->child( 'about', 'index.html' ), '/about does not exist';
ok !-e $config_to->child( 'logo-white-2x.png' ), 'image is not exported';

done_testing;

__DATA__
@@ index.html.ep
<head>
    <link rel="stylesheet" href="//cdnjs.org/bootstrap.css">
</head>
<h1>Export</h1>
<a href="http://mojolicious.org"><img src="logo-white-2x.png"></a>
<a href="/docs">Absolute</a>
<a href="about">Relative</a>

@@ docs.html.ep
<h1>Docs</h1>
<a href="/docs/more">More Docs</a>

@@ docs/more.html.ep
<h1>More Docs</h1>

@@ about.html.ep
<h1>About</h1>
<a href="/">Back to home</a>

@@ logo-white-2x.png (base64)
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