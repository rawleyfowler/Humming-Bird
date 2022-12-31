# Humming-Bird
Humming-Bird is a simple, composable, and performant, all in one HTTP web-framework for Raku.
Humming-Bird was inspired mainly by [Opium](https://github.com/rgrinberg/opium), [Sinatra](https://sinatrarb.com), and [Express](https://expressjs.com), and tries to keep
things relatively simple, allowing the user to pull in things like templating engines,
and ORM's on their own terms.

Humming-Bird comes with what you need to quickly, and efficiently spin up REST API's, and with a few small plugins, dynamic MVC style web-apps.

## Examples

#### Simple example:
```raku
use v6;

use Humming-Bird::Core;

get('/', -> $request, $response {
    $response.html('<h1>Hello World</h1>');
});

listen(8080);

# Navigate to localhost:8080!
```

#### Simple JSON example:
```raku
use v6;

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

## License
Humming-Bird is available under the MIT, you can view the license in the `LICENSE` file
at the root of the project. For more information about the MIT, please click
[here](https://mit-license.org/).
