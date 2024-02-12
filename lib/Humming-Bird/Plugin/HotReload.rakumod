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
            $.backend.close;
            self!start-server();
        }
    }

    method !start-server {
        start {
            listen(self.port, self.addr, );
        }
    }

    method !observe {
        
    }
}

method register($server is rw, %routes, @middleware, @advice, **@args) {
    die 'Humming-Bird::Backend::HotRealod is WIP. Please do not use it yet.';
    $server = Humming-Bird::Backend::HotReload.new(backend => $server);
    CATCH {
        default {
            warn 'Failed to find or parse your ".humming-bird.json" configuration. Ensure your file is well formed, and does exist.';
        }
    }
}
