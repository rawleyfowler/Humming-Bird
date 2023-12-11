use Humming-Bird::Plugin;
use Humming-Bird::Middleware;
use Humming-Bird::Advice;

unit class Humming-Bird::Plugin::Logger does Humming-Bird::Plugin;

method register($server, %routes, @middleware is rw, @advice is rw, **@args) {
    @middleware.unshift: &middleware-logger;
    @advice.unshift: &advice-logger;
}
