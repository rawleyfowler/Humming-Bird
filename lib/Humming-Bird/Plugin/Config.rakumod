use JSON::Fast;
use Humming-Bird::Plugin;
use Humming-Bird::Core;

unit class Humming-Bird::Plugin::Config does Humming-Bird::Plugin;

method register($server, %routes, @middleware, @advice, **@args) {
    my $filename = @args[0] // '.humming-bird.json';
    my %config = from-json($filename.IO.slurp // '{}');

    return %(
        config => sub (Humming-Bird::Glue::HTTPAction $a) { %config }
    );

    CATCH {
        default {
            warn 'Failed to find or parse your ".humming-bird.json" configuration. Ensure your file is well formed, and does exist.';
        }
    }
}
