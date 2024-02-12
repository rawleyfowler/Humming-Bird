use Humming-Bird::Core;
use JSON::Fast;

# Create database with:
# sqlite3 mydb.db < create-db.sql

# Tell Humming-Bird::Plugin::DBIish where to look for your db.
plugin 'DBIish', ['SQLite', :database<mydb.db>];

get '/users', sub ($request, $response) {
    my $sth = $request.db.execute(q:to/SQL/);
    SELECT * FROM users
    SQL
    my $json = to-json($sth.allrows(:array-of-hash));
    return $response.json($json);
}

post '/users', sub ($request, $response) {
    my $sth = $request.db.prepare(q:to/SQL/);
    INSERT INTO users (name, age)
    VALUES (?, ?)
    RETURNING *
    SQL

    my $content = $request.content;
    $sth = $sth.execute($content<name>, $content<age>);
    
    my $json = to-json($sth.allrows(:array-of-hash));
    return $response.json($json);
}

listen(8080);
