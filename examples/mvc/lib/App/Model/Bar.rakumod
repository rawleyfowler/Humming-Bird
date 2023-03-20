unit class App::Foo::Model::Bar;

our @bars = [];

submethod get-all {
    @bars;
}

submethod get-by-id(Str:D $id) {
    @bars.first(*.<id> eq $id);
}

submethod validate($bar) {
    $bar.<id> and $bar.<coordinates> and $bar.<temperature>;
}

submethod save($bar) {
    @bars.push: $foo;
}
