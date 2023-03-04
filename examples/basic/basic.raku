use v6;
use strict;

use Humming-Bird::Core;
use Humming-Bird::Middleware;
use Humming-Bird::Advice;

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
}, [ &middleware-logger ]); # m_logger is provided by Humming-Bird::Middleware


# Custom Middleware example
sub block_firefox($request, $response, &next) {
    if $request.header('User-Agent').starts-with('Mozilla') {
        return $response.status(400); # Bad Request!
    }

    next(); # Otherwise continue
}

get('/firefox-not-allowed', -> $request, $response {
    $response.html('<h1>Hello Non-firefox user!</h1>');
}, [ &middleware-logger, &block_firefox ]); # Many middlewares can be combined.

# Grouping routes
# group: @route_callbacks, @middleware
group([
    &get.assuming('/hello', -> $request, $response {
        $response.html('<h1>Hello!</h1>');
    }),

    &get.assuming('/hello/world', -> $request, $response {
        $response.html('<h1>Hello World!</h1>');
    })
], [ &middleware-logger, &block_firefox ]);


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
        $response.cookie('AUTH', 'logged in!', DateTime.now + Duration.new(3600)).html('You logged in!');
    } else {
        $response.status(400);
    }
});


# Redirects
get('/take/me/home', -> $request, $response {
    $response.redirect('/', :permanent); # Do not provide permanent for a status of 307.
});


# Error throwing exception
get('/throws-error', -> $request, $response {
    $response.html('abc.html'.IO.slurp);
});

# Error handler
error(X::AdHoc, -> $exn, $response { $response.status(500).write("Encountered an error. <br> $exn") });

# After middleware, Response --> Response
advice(&advice-logger);


# Static content
static('/static', '/var/www/static'); # Server static content on '/static', from '/var/www/static'

get('/favicon.ico', sub ($request, $response) { $response.file('favicon.ico'); });

# Routers
my $router = Router.new(root => '/foo');
$router.middleware(&middleware-logger); # Append this middleware to all proceeding routes
$router.advice(&advice-logger); # Append this advice to all proceeding routes
$router.get(-> $request, $response { $response.write('foo') });
$router.post(-> $request, $response { $response.write('foo post!') });
$router.get('/bar', -> $request, $response { $response.write('foo bar') }); # Registered on /foo/bar

# Run the application
listen(9000, timeout => 3); # You can set timeout, to a value you'd like (this is how long keep-alive sockets are kept open) default is 5 seconds.
# You can also set the :no-block adverb to stop the call from blocking, and be run on the task scheduler.

# vim: expandtab shiftwidth=4
