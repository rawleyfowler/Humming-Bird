use MONKEY-TYPING;
use Humming-Bird::Plugin;
use Humming-Bird::Core;

unit class Humming-Bird::Plugin::DBIish does Humming-Bird::Plugin;

my %databases;

method register($server, %routes, @middleware, @advice, **@args) {
    my $database-name = 'default';
    my @database-args;

    if @args.elems == 1 {
        if @args[0].isa(Array) || @args[0].isa(List) {
            @database-args = |@args[0];
        } else {
            $database-name = @args[0];
        }
    } else {
        $database-name = @args[0];
        @database-args = |@args[1];
    }

    try {
        require ::('DBIish');
        CATCH {
            default {
                die 'DBIish is not installed, to use Humming-Bird::Plugin::DBIish, please install DBIish. "zef install DBIish"'
            }
        }
    }

    without @database-args {
        die 'Invalid configuration for Humming-Bird::Plugin::DBIish, please provide arguments.'
    }

    if (%databases.keys.elems == 0) {
        augment class Humming-Bird::Glue::HTTPAction {
            method db(Str $database = 'default') {
                %databases{$database};
            }
        }
    }

    use DBIish;
    %databases{$database-name} = DBIish.connect(|@database-args);

    CATCH {
        default {
            die 'Failed to setup Humming-Bird::Plugin::DBIish cause: $_';
        }
    }
}

