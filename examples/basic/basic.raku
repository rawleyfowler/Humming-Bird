use v6;
use strict;

use Humming-Bird::Core;
use Humming-Bird::Middleware;

# Simple static routes
get('/', -> $request, $response {
    $response.html('<h1>Hello World!</h1>');
});


# Path parameters
get('/:user', -> $request, $response {
    my $user = $request.param('user');
    $response.html(sprintf('<h1>Hello %s</h1>', $user));
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


# Simple Middleware example
get('/logged', -> $request, $response {
    $response.html('<h1>Your request has been logged. Check the console.</h1>');
}, [ &m_logger ]); # m_logger is provided by Humming-Bird::Middleware


# Custom Middleware example
sub block_firefox($request, $response, &next) {
    if $request.header('User-Agent').starts-with('Mozilla') {
        return $response.status(400); # Bad Request!
    }

    next(); # Otherwise continue
}

get('/firefox-not-allowed', -> $request, $response {
    $response.html('<h1>Hello Non-firefox user!</h1>');
}, [ &m_logger, &block_firefox ]); # Many middlewares can be combined.

# Grouping routes
# group: @route_callbacks, @middleware
group([
    &get.assuming('/hello', -> $request, $response {
        $response.html('<h1>Hello!</h1>');
    }),

    &get.assuming('/hello/world', -> $request, $response {
        $response.html('<h1>Hello World!</h1>');
    })
], [ &m_logger, &block_firefox ]);


# Simple cookie

# Middleware to make sure you have an AUTH cookie
sub authorized($request, $response, &next) {
    without $request.cookie('AUTH') {
        return $response.status(403);
    }

    &next();
}

get('/auth/home', -> $request, $response {
    $response.html('You are logged in!');
}, [ &authorized ]);

post('/auth/login', -> $request, $response {
    if $request.body eq 'Password123' {
        # TODO: Implement redirects
        $response.cookie('AUTH', 'logged in!', LocalTime.now + Duration.new(3600)).html('You logged in!');
    } else {
        $response.status(400);
    }
});


# Run the application
listen(8080);

# vim: expandtab shiftwidth=4
