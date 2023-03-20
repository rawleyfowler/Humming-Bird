use Humming-Bird::Core;

use App::Foo::Model::Foo;
use App::Foo::Render;

unit module App::Foo::Controller::Foo;

my $router = Router.new(base => '/foo');

$router.get(-> $request, $response {
    my $foos = Foo.get-all;
    $response.html(render('foos', :$foos));
});

$router.post(-> $request, $response {
    my $json = $request.content;

    return $response.html('400 Bad Request').status(400) unless Foo.validate($json);

    Foo.save($json);
    $response.status(201); # 201 Created
});

$router.get('/:id', -> $request, $response {
    my $foo = Foo.get-by-id: $request.param('id');

    return $response.html('404 Not Found').status(404) unless $foo;
    
    $response.html(render('foo', :$foo));
});
