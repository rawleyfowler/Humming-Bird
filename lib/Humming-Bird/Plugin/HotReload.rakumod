use MONKEY-TYPING;
use Humming-Bird::Plugin;
use Humming-Bird::Core;
use Humming-Bird::Backend;

unit class Humming-Bird::Plugin::HotReload does Humming-Bird::Plugin;

class Humming-Bird::Backend::HotReload does Humming-Bird::Backend {
    has $.backend handles <port addr timeout>;
    has Channel:D $!reload-chan .= new;
    method listen(&handler) {
        self!observe();
        self!start-server();

        react whenever $!reload-chan -> $reload {
            if ($reload === True) {
                $.backend.close; 
                self!start-server();
            }
        }
    }

    method !start-server {
        start {
            listen(self.port, self.addr);
        }
    }

    method !observe {
        react whenever IO::Notification.watch-path('.') {
            say "$^file changed, reloading Humming-Bird...";
            $!reload-chan.send: True;
        }
    }
}

method register($server is rw, %routes, @middleware, @advice, **@args) {
    $server := Humming-Bird::Backend::HotReload.new(backend => $server, timeout => 3);
}
