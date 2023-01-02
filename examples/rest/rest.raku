# A simple REST API using Humming-Bird::Core and JSON::Fast

use v6;
use strict;

use Humming-Bird::Core;
use JSON::Fast <immutable>;

# Basic model to represent our User
class User {
    has Str $.name  is required;
    has Int $.age   is required;
    has Str $.email is required;

    method to-json {
        to-json({:$!name, :$!age, :$!email});
    }

    submethod from-json($json) {
        User.new($json.List);
    }
}

# Fake DB, you can pull in DBIish if you need a real DB.
my @user-database;


get('/users', -> $request, $response {
    $response.json: to-json(@user-database.map(*.to-json));
});

post('/users', -> $request, $response {
    say $request.raku;
    $response.json($request.body ~ "}"); # 204 Created
});

listen(8080);

# vim: expandtab shiftwidth=4
