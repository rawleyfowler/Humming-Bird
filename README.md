# Humming-Bird
![Zef Badge](https://raku.land/zef:rawleyfowler/Humming-Bird/badges/version?)
[![SparrowCI](https://ci.sparrowhub.io/project/gh-rawleyfowler-Humming-Bird/badge)](https://ci.sparrowhub.io)

**Here be dragons**: Humming-Bird is still young, you may run into bugs, creatures, and daemons, if you run into any issues, please make an [issue](https://github.com/rawleyfowler/Humming-Bird/issues)!

Humming-Bird is a simple, composable, and performant, all in one HTTP web-framework for Raku.
Humming-Bird was inspired mainly by [Opium](https://github.com/rgrinberg/opium), [Sinatra](https://sinatrarb.com), and [Express](https://expressjs.com), and tries to keep
things minimal, allowing the user to pull in things like templating engines, and ORM's on their own terms.

Humming-Bird comes with what you need to quickly, and efficiently spin up REST API's, and with a few of the users favorite libraries, dynamic MVC style web-apps.

Humming-Bird is not meant to face the internet directly. Please use a reverse proxy such as httpd or NGiNX.

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

#### Simple JSON example:
```raku
use v6.d;

use Humming-Bird::Core;

my %users = Map.new('bob', '{ "name": "bob" }', 'joe', '{ "name": "joe" }');

get('/users/:user', -> $request, $response {
    my $user = $request.param('user');

    if %users{$user}:exists {
        $response.json(%users{$user});
    } else {
        $response.status(404);
    }
});

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

# Scoped middleware

# Both of these routes will now share the middleware specified in the last parameter of the group.
group([
    &get.assuming('/', -> $request, $response {
        $response.write('Index');
    }),

    &post.assuming('/users', -> $request, $response {
        $response.write($request.body).status(204);
    })
], [ &middleware-logger, &block-firefox ]);
```

More examples can be found in the [examples](https://github.com/rawleyfowler/Humming-Bird/tree/main/examples) directory.

## Design
- Humming-Bird should be easy to pickup, and simple for developers new to Raku and/or web development.
- Humming-Bird is not designed to be exposed to the internet directly. You should hide Humming-Bird behind a reverse-proxy like NGiNX or httpd.
- Simple and composable via middlewares.

## Things to keep in mind
- This project is in active development, things will break.
- You may run into bugs.
- **Not** production ready, yet.

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

## Contributing
All contributions are encouraged! I know the Raku community is amazing, so I hope to see
some people get involved :D

Please make sure you squash your branch, and name it accordingly before it gets merged!

Before submitting any feature/code pull requests, ensure that the following passes:
```bash
cd Humming-Bird
prove6 -I. t/ it/
```

## License
Humming-Bird is available under the MIT, you can view the license in the `LICENSE` file
at the root of the project. For more information about the MIT, please click
[here](https://mit-license.org/).
