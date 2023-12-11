use Humming-Bird::Plugin;
use Humming-Bird::Middleware;
use Humming-Bird::Advice;

unit class Humming-Bird::Plugin::Session does Humming-Bird::Plugin;

method register($server, %routes, @middleware, @advice, **@args) {
    @middleware.push: &middleware-session;
}
