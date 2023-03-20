use Humming-Bird::Core;

use App::Foo::Model::Bar;
use App::Foo::Render;

unit module App::Foo::Controller::Bar;

my $router = Router.new(base => '/bar');

$router.get(-> $request, $response {
    my $bars = Bar.get-all;
    $response.html(render('bars', :$bars));
});

$router.post(-> $request, $response {
    my $json = $request.content;

    return $response.html('400 Bad Request').status(400) unless Bar.validate($json);

    Bar.save($json);
    $response.status(201); # 201 Created
});

$router.get('/:id', -> $request, $response {
    my $bar = Bar.get-by-id: $request.param('id');

    return $response.html('404 Not Found').status(404) unless $bar;
    
    $response.html(render('bar', :$bar));
});
