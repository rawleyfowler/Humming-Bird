use v6.d;

use Humming-Bird::Core;

get('/', -> $request, $response {
    $response.html('<h1>Hello from Docker.</h1>');
});

listen(8080);
