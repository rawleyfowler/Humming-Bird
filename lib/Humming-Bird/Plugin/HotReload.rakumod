use MONKEY-TYPING;
use Humming-Bird::Plugin;
use Humming-Bird::Core;
use Humming-Bird::Backend;
use File::Find;

unit class Humming-Bird::Plugin::HotReload does Humming-Bird::Plugin;

my $temp-file = '/tmp/.humming-bird.hotreload' || $*CWD ~ '/.humming-bird.hotreload';

my sub find-dirs(IO::Path:D $dir) {
    slip $dir.IO, slip find :$dir, :type<dir>
}

# Credits to: https://github.com/raku-community-modules/IO-Notification-Recursive
sub watch-recursive(IO(Cool) $start, Bool :$update) is export {
    supply {
        my sub watch-it(IO::Path:D $io) {
            whenever $io.watch -> $e {
                if $update {
                    if $e.event ~~ FileRenamed && $e.path.d {
                        watch-it($_) for find-dirs $e.path;
                    }
                }
                emit $e;
            }
        }
        watch-it($_) for find-dirs $start;
    }
}

class Humming-Bird::Backend::HotReload does Humming-Bird::Backend {
    has $!should-refresh = False;
    has $!proc;

    method listen(&handler) {
        self!observe();
        self!start-server();

        say "\n" ~ 'Humming-Bird HotReload PID: ' ~ (await $!proc.pid) ~ "\n";

        react {
            whenever signal(SIGINT) { $temp-file.IO.unlink; exit; }
            whenever Supply.interval(1, 2) {
                if ($!should-refresh) {
                    say 'File change detected, refreshing Humming-Bird...';
                    self!kill-server();
                    self!start-server();
                    $!should-refresh = False;
                }
            }
        }
    }

    method !kill-server {
        $!proc.kill(9);
    }

    method !start-server {
        # Devious, evil, dangerous, hack for HotReload.... :)
        my $contents = $*PROGRAM-NAME.IO.slurp;
        $contents = $contents.subst(/plugin\s\'?\"?HotReload\'?\"?';'?/, '', :g); 

        try shell 'reset';

        $temp-file.IO.spurt: $contents;
        $!proc = Proc::Async.new('raku', $temp-file);
        $!proc.bind-stdout($*OUT);
        $!proc.bind-stderr($*ERR);
        $!proc.start;
    }

    method !observe {
        my $observer = watch-recursive('.');
        $observer.tap({
            Lock.new.protect({ $!should-refresh = True; }) unless $^file.path.ends-with($temp-file);
        });
    }
}

method register($server is rw, %routes, @middleware, @advice, **@args) {
    $server = Humming-Bird::Backend::HotReload.new(timeout => 1);
}
