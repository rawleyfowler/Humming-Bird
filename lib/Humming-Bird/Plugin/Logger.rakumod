use Humming-Bird::Plugin;
use Humming-Bird::Middleware;
use Humming-Bird::Advice;

unit class Humming-Bird::Plugin::Logger does Humming-Bird::Plugin;

sub pre-logger($file, $request, $response, &next) {
    $request.log(sprintf("%s | %s | %s | %s", $request.method.Str, $request.path, $request.version, $request.header('User-Agent') || 'Unknown Agent'), :$file);
    &next();
}

sub post-logger($file, $response) {
    my $log = "{ $response.status.Int } { $response.status } | { $response.initiator.path } | ";
	$log ~= $response.header('Content-Type') ?? $response.header('Content-Type') !! "No Content";
	$response.log: $log;
}

method register($server, %routes, @middleware, @advice, **@args) {
    my $file = @args[0] ?? @args[0].IO !! $*OUT;
    @middleware.prepend: &pre-logger.assuming($file);
    @advice.prepend: &post-logger.assuming($file);
}
