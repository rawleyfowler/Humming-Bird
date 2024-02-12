use MONKEY;
use Humming-Bird::Plugin;
use Humming-Bird::Core;

unit class Humming-Bird::Plugin::DBIish does Humming-Bird::Plugin;

my %databases;

method register($server, %routes, @middleware, @advice, **@args) {
    my $dbiish = try "use DBIish; DBIish".EVAL;

    if $dbiish ~~ Nil {
        die 'You do not have DBIish installed, please install DBIish to use Humming-Bird::Plugin::DBIish.';
    }

    if @args.elems < 1 {
        die "Invalid configuration for Humming-Bird::Plugin::DBIish, please provide more arguments.\n\nExample: `plugin 'DBIish', ['SQLite', 'mydb.db']`";
    }

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

    if (%databases.keys.elems == 0) {
        augment class Humming-Bird::Glue::HTTPAction {
            method db(Str $database = 'default') {
                %databases{$database};
            }
        }
    }

    my $dh = $dbiish.install-driver(shift @database-args);

    say @database-args;
    %databases{$database-name} = $dh.connect(|%(|@database-args));

    CATCH {
        default {
            die "Failed to setup Humming-Bird::Plugin::DBIish cause:\n\n$_";
        }
    }
}

