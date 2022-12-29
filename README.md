# Humming-Bird
Humming-Bird is a simple, composable, and performant, all in one HTTP web-framework for Raku.
Humming-Bird was inspired mainly by [Opium](https://github.com/rgrinberg/opium), [Sinatra](https://sinatrarb.com), and [Express](https://expressjs.com), and tries to keep
things relatively simple, allowing the user to pull in things like templating engines,
and ORM's on their own terms. Humming-Bird comes with what you need to quickly, and efficiently spin up REST API's, and static web-apps. To top it all off, Humming-Bird has very few dependencies, just Test, and [HTTPStatus](https://github.com/lizmat/HTTP-Status).

## Things to keep in mind
- This project is in active development, things will break.
- You may run into bugs.
- A few major web-framework features are missing (mainly middleware)
- **Not** production ready, yet.

## How to install
Make sure you have [zef](https://github.com/ugexe/zef) installed.
```bash
zef -v install https://github.com/rawleyfowler/Humming-Bird.git
```

## Contributing
All contributions are encouraged! I know the Raku community is amazing, so I hope to see
some people get involved :D

Please make sure you squash your branch, and name it accordingly before it gets merged!

## License
Humming-Bird is available under the MIT, you can view the license in the `LICENSE` file
at the root of the project. For more information about the MIT, please click
[here](https://mit-license.org/).
