unit class App::Foo::Model::Foo;

our @foos = [];

submethod get-all {
    @foos;
}

submethod get-by-id(Str:D $id) {
    @foos.first(*.<id> eq $id);
}

submethod validate($foo) {
    $foo.<id> and $foo.<name> and $foo.<age>;
}

submethod save($foo) {
    @foos.push: $foo;
}
