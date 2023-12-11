use JSON::Fast;
use MONKEY-TYPING;
use Humming-Bird::Plugin;
use Humming-Bird::Core;

unit class Humming-Bird::Plugin::Config does Humming-Bird::Plugin;

method register($server, %routes, @middleware, @advice, **@args) {
    my $filename = @args[0] // '.humming-bird.json';
    my %config = from-json($filename.IO.slurp // '{}');

    augment class Humming-Bird::Glue::HTTPAction {
        method config(--> Hash:D) {
            %config;
        }
    }

    CATCH {
        default {
            warn 'Failed to find or parse your ".humming-bird.json" configuration. Ensure your file is well formed, and does exist.';
        }
    }
}
