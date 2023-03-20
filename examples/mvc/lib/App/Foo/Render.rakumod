use Template::Mustache;

unit module App::Foo::Render;

my $templater = Template::Mustache.new(:from('templates'));

submethod CALL-ME(Str:D $tmpl, *%args --> Str:D) {
    $templater.render($tmpl, { :$title, |%args });
}
