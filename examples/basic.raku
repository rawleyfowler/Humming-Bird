use v6;
use strict;

use Humming-Bird::Core;

# Simple static routes
get('/', -> $request, $response {
    $response.html('<h1>Hello World!</h1>');
});

# Path parameters
get('/:user', -> $request, $response {
    my $user = $request.param('user');
    $response.html(sprintf('<h1>Hello %s</h1>', $user));
});

get('/favicon.ico', -> $request, $response {
    $response.html("No favico sorry :L");
});

# Query parameters
post('/password', -> $request, $response {
    my $super_secret_password = '1234';
    my $password = $request.query('password') || 'Wrong!'; # /password?password=
    if $password eq $super_secret_password {
        $response.html('<h1>That password was correct!</h1>'); # Responses default to 200, change the with .status
    } else {
        $response.status(400).html('<h1>Wrong Password!!!</h1>');
    }
});

# Serving Files
get('/help.txt', -> $request, $response {
    $response.file('basic.txt').content_type('text/plain');
});

listen(8080);

# vim: expandtab shiftwidth=4
