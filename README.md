<div style="text-align: center;">
<h1>Humming-Bird</h1>

<img src="https://user-images.githubusercontent.com/75388349/222969311-216081eb-fe47-4f97-bc49-d52fc8750a24.svg" />

![Zef Badge](https://raku.land/zef:rawleyfowler/Humming-Bird/badges/version?)
[![SparrowCI](https://ci.sparrowhub.io/project/gh-rawleyfowler-Humming-Bird/badge)](https://ci.sparrowhub.io)
</div>

Humming-Bird is a simple, composable, and performant web-framework for Raku on MoarVM.
Humming-Bird was inspired mainly by [Sinatra](https://sinatrarb.com), and [Express](https://expressjs.com), and tries to keep
things minimal, allowing the user to pull in things like templating engines, and ORM's on their own terms.

## Features
Humming-Bird has 2 simple layers, at the lowest levels we have `Humming-Bird::Glue` which is a simple "glue-like" layer for interfacing with
`Humming-Bird::Backend`'s. 
Then you have the actual application logic in `Humming-Bird::Core` that handles: routing, middleware, error handling, cookies, etc.

- Powerful function composition based routing and application logic
    - Routers
    - Groups
    - Middleware
    - Advice (end of stack middleware)
    - Simple global error handling
    - Plugin system

- Simple and helpful API
    - get, post, put, patch, delete, etc
    - Request content will be converted to the appropriate Raku data-type if possible
    - Static files served have their content type infered
    - Request/Response stash's for inter-layer route talking

- Swappable backends

**Note**: Humming-Bird is not meant to face the internet directly. Please use a reverse proxy such as Apache, Caddy or NGiNX.

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

See [this](https://github.com/rawleyfowler/Humming-Bird/issues/43#issuecomment-1454252501) for a more detailed performance preview
vs. Ruby's Sinatra using `Humming-Bird::Backend::HTTPServer`.

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
        $response.json(to-json %users{$user});
    } else {
        $response.status(404).html("Sorry, $user does not exist.");
    }
});

post('/users', -> $request, $response {
    my %user = $request.content; # Different from $request.body, $request.content will do its best to decode the data to a Map.
    if my-user-validation-logic(%user) { # Validate somehow, i'll leave that up to you.
        %users{%user<name>} = %user;
        $response.status(201); # 201 created
    } else {
        $response.status(400).html('Bad request');
    }
});

listen(8080);
```

#### Using plugins
```raku
use v6.d;

use Humming-Bird::Core;

plugin 'Logger'; # Corresponds to the pre-built Humming-Bird::Plugin::Logger plugin.
plugin 'Config'; # Corresponds to the pre-built Humming-Bird::Plugin::Config plugin.

get('/', sub ($request, $response) {
    my $database_url = $request.config<database_url>;
    $response.html("Here's my database url :D " ~ $database_url);
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

plugin 'Logger';

$router.get(-> $request, $response { # Register a GET route on the root of the router
    $response.html('<h1>Hello World</h1>');
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

listen(8080);
```

Since Humming-Bird `3.0.4` it may be more favorable to use plugins to register global middlewares.

#### Swappable Backends
```raku
use v6.d;

use Humming-Bird::Core;

get('/', -> $request, $response {
    $response.html('This request has been logged!');
});

# Run on a different backend, assuming: 
listen(:backend(Humming-Bird::Backend::MyBackend));
```

More examples can be found in the [examples](https://github.com/rawleyfowler/Humming-Bird/tree/main/examples) directory.

## Swappable backends

In Humming-Bird `3.0.0` and up you are able to write your own backend, please follow the API outlined by the `Humming-Bird::Backend` role,
and view `Humming-Bird::Backend::HTTPServer` for an example of how to implement a Humming-Bird backend.

## Plugin system

Humming-Bird `3.0.4` and up features the Humming-Bird Plugin system, this is a straight forward way to extend Humming-Bird with desired functionality before the server
starts up. All you need to do is create a class that inherits from `Humming-Bird::Plugin`, for instance `Humming-Bird::Plugin::OAuth2`, expose a single method `register` which
takes arguments that align with the arguments specified in `Humming-Bird::Plugin.register`, for more arguments, take a slurpy at the end of your register method.

Here is an example of a plugin:

```raku
use MONKEY-TYPING;
use JSON::Fast;
use Humming-Bird::Plugin;
use Humming-Bird::Core;

unit class Humming-Bird::Plugin::Config does Humming-Bird::Plugin;

method register($server, %routes, @middleware, @advice, **@args) {
    my $filename = @args[0] // '.humming-bird.json';
    my %config = from-json($filename.IO.slurp // '{}');

    augment class Humming-Bird::Glue::HTTPAction {
        method config(--> Hash:D) {
            %config;
        }
    }

    CATCH {
        default {
            warn 'Failed to find or parse your ".humming-bird.json" configuration. Ensure your file is well formed, and does exist.';
        }
    }
}
```

This plugin embeds a `.config` method on the base class for Humming-Bird's Request and Response classes, allowing your config to be accessed during the request/response lifecycle.

Then to register it in a Humming-Bird application:

```raku
use Humming-Bird::Core;

plugin 'Config', 'config/humming-bird.json'; # Second arg will be pushed to he **@args array in the register method.

get('/', sub ($request, $response) {
    $response.write($request.config<foo>); # Echo back the <foo> field in our JSON config.
});

listen(8080);
```

## Design
- Humming-Bird should be easy to pickup, and simple for developers new to Raku and/or web development.
- Humming-Bird is not designed to be exposed to the internet directly. You should hide Humming-Bird behind a reverse-proxy like NGiNX, Apache, or Caddy.
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

Install App::Prove6

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
