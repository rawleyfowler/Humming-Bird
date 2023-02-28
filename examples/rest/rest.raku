# A simple REST API using Humming-Bird::Core and JSON::Marshal/Unmarshal

# Test it with this
# curl -X post http://localhost:8080/users -d '{ "name": "bob", "age": 13, "email": "bob@gmail.com" }' -v

use v6;
use strict;

use Humming-Bird::Core;
use Humming-Bird::Middleware;
use Humming-Bird::Advice;
use JSON::Marshal;
use JSON::Unmarshal;

# Basic model to represent our User
class User {
    has Str $.name  is required;
    has Int $.age   is required;
    has Str $.email is required;
}

class X::NotFound is X::AdHoc { }

# Fake DB, you can pull in DBIish if you need a real DB.
my @user-database = User.new(name => 'bob', age => 22, email => 'bob@bob.com');

get('/', -> $request, $response { $response.redirect('/users', :permanent) });

get('/users', -> $request, $response {
    $response.json(marshal(@user-database));
}, [ &middleware-logger ]);

get('/users/:name', -> $request, $response {
    my $name = $request.params<name>;
    my $user = @user-database.first(*.name eq $name);       
    die X::NotFound.new unless $user;
    $response.json(marshal($user));
});

post('/users', -> $request, $response {
    my $user := unmarshal($request.body, User);
    @user-database.push($user);
    # Simulate logging in
    $response.cookie('User', $user.name, DateTime.now + Duration.new(3600)); # One Hour
    $response.status(204).json(marshal($user)); # 204 Created
});

error(X::NotFound, -> $exn, $response { $response.status(404).write('Requested resource not found!') });

advice(&advice-logger); # advice-logger is provided by Humming-Bird::Advice

listen(8000);

# vim: expandtab shiftwidth=4
