# Humming-Bird
![Zef Badge](https://raku.land/zef:rawleyfowler/Humming-Bird/badges/version?)
[![SparrowCI](https://ci.sparrowhub.io/project/gh-rawleyfowler-Humming-Bird/badge)](https://ci.sparrowhub.io)

Humming-Bird is a simple, composable, and performant web-framework for Raku on MoarVM.
Humming-Bird was inspired mainly by [Sinatra](https://sinatrarb.com), and [Express](https://expressjs.com), and tries to keep
things minimal, allowing the user to pull in things like templating engines, and ORM's on their own terms.

Humming-Bird provides a rich API for crafting HTTP responses, as well as a few nice quality-of-life features like
infered data encoding, meaning you shouldn't ever have to parse JSON to a Raku map again, a simple functional interface
allowing users to compose functions together to create their routes, middlewares, and advice, a simple error handling system
for ensuring stability, and crazy fast routing system.

Humming-Bird comes with what you need to quickly, and efficiently spin up REST API's, static sites, 
and with a few of the users favorite libraries, dynamic MVC style web-apps. Humming-Bird stays out of your way
letting you structure your code however you like.

**Note**: Humming-Bird is not meant to face the internet directly. Please use a reverse proxy such as httpd or NGiNX.

## How to install
Make sure you have [zef](https://github.com/ugexe/zef) installed.

#### Install latest
```bash
zef -v install https://github.com/rawleyfowler/Humming-Bird.git
```

#### Install stable
```bash
zef install Humming-Bird
```

## Performance
Around ~20% faster than Ruby's `Sinatra`, and only improving as time goes on!

See [this](https://github.com/rawleyfowler/Humming-Bird/issues/43#issuecomment-1454252501) for a more detailed performance preview.

## Examples

#### Simple example:
```raku
use v6.d;

use Humming-Bird::Core;

get('/', -> $request, $response {
    $response.html('<h1>Hello World</h1>');
});

listen(8080);

# Navigate to localhost:8080!
```

#### Simple JSON CRUD example:
```raku
use v6.d;

use Humming-Bird::Core;
use JSON::Fast; # A dependency of Humming-Bird

my %users = Map.new('bob', %('name', 'bob'), 'joe', %('name', 'joe'));

get('/users/:user', -> $request, $response {
    my $user = $request.param('user');

    if %users{$user}:exists {
        $response.json(to-json: %users{$user});
    } else {
        $response.status(404).html("Sorry, $user does not exist.");
    }
});

post('/users', -> $request, $response {
    my %user = $request.content; # Different from $request.body, $request.content will do its best to encode the data to a Map.
    if my-user-validation-logic(%user) { # Validate somehow, i'll leave that up to you.
        %users{%user<name>} = %user;
        $response.status(204); # 204 created
    } else {
        $response.status(400).html('Bad request');
    }
});

listen(8080);
```

#### Routers
```raku
use v6.d;

use Humming-Bird::Core;
use Humming-Bird::Middleware;

# NOTE: Declared routes persist through multiple 'use Humming-Bird::Core' statements
# allowing you to declare routing logic in multiple places if you want. This is true
# regardless of whether you're using the sub or Router process for defining routes.
my $router = Router.new(root => '/');

$router.middleware(&middleware-logger); # middleware-logger is provided by the Middleware package

$router.get(-> $request, $response { # Register a GET route on the root of the router
    $response.html('<h1>Hello World</h1>);
});

$router.get('/foo', -> $request, $response { # Register a GET route on /foo
    $response.html('<span style="color: blue;">Bar</span>');
});

my $other-router = Router.new(root => '/bar');

$other-router.get('/baz', -> $request, $response { # Register a GET route on /bar/baz
    $response.file('hello-world.html'); # Will render hello-world.html and infer its content type
});

# No need to register routers, it's underlying routes are registered with Humming-Bird on creation.
listen(8080); 
```

#### Middleware
```raku
use v6.d;

use Humming-Bird::Core;
use Humming-Bird::Middleware;

get('/logged', -> $request, $response {
    $response.html('This request has been logged!');
}, [ &middleware-logger ]); # &middleware-logger is provided by Humming-Bird::Middleware

# Custom middleware
sub block-firefox($request, $response, &next) {
    return $response.status(400) if $request.header('User-Agent').starts-with('Mozilla');
    $response.status(200);
}

get('/no-firefox', -> $request, $response {
    $response.html('You are not using Firefox!');
}, [ &middleware-logger, &block-firefox ]);
```

More examples can be found in the [examples](https://github.com/rawleyfowler/Humming-Bird/tree/main/examples) directory.

## Design
- Humming-Bird should be easy to pickup, and simple for developers new to Raku and/or web development.
- Humming-Bird is not designed to be exposed to the internet directly. You should hide Humming-Bird behind a reverse-proxy like NGiNX or httpd.
- Simple and composable via middlewares.

## Things to keep in mind
- This project is in active development, things will break.
- You may run into bugs.
- This project is largely maintained by one person.

## Contributing
All contributions are encouraged! I know the Raku community is amazing, so I hope to see
some people get involved :D

Please make sure you squash your branch, and name it accordingly before it gets merged!

#### Testing

Install App::prove6

```bash
zef install --force-install App::Prove6
```

Ensure that the following passes:

```bash
cd Humming-Bird
zef install . --force-install --/test
prove6 -v -I. t/ it/
```

## License
Humming-Bird is available under the MIT, you can view the license in the `LICENSE` file
at the root of the project. For more information about the MIT, please click
[here](https://mit-license.org/).
