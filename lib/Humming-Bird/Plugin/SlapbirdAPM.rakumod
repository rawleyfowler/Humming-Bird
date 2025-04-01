use Humming-Bird::Plugin;
use Humming-Bird::Core;
use Cro::HTTP::Client;

unit class Humming-Bird::Plugin::SlapbirdAPM does Humming-Bird::Plugin;

has Channel:D $.channel .= new;
has $.lockout = False;
has DateTime $.last_lockout;

method register($server, %routes, @middleware, @advice, **@args) {
    my $key = @args[0] // %*ENV<SLAPBIRDAPM_KEY>;
    my $base-uri = %*ENV<SLAPBIRDAPM_URI> // 'https://slapbirdapm.com';

    if (!$key) {
        die 'No SlapbirdAPM key set, either pass it or use the SLAPBIRDAPM_KEY environment variable!';
    }

    my $http = Cro::HTTP::Client.new: :$base-uri, headers => [ x-slapbird-apm => $key ];

    start react {
        whenever $.channel {
            CATCH { default { warn $_ } }
            my $request = $_<request>;
            my $response = $_<response>;
            my $start_time = $_<start_time>;
            my $end_time = $_<end_time>;
            my $error = $_<error>;

            my %json = (
                type => 'raku',
                method => $request.method,
                end_point => $request.path,
                start_time => $start_time,
                end_time => $end_time,
                response_code => $response.status.code,
                response_size => $response.body.bytes,
                response_headers => $response.headers,
                request_id => $request.context-id,
                request_size => $request.body.bytes,
                request_headers => $request.headers,
                error => $error,
                requestor => $request.headers<x-slapbird-name> // 'UNKNOWN',
                handler => 'Humming-Bird',
                stack => [],
                queries => [],
                num_queries => 0,
                os => $*VM.osname(),
            );

            my $r = await $http.post('/apm',
            content-type => "application/json",
            body => %json);

            if ($r.status == 429) {
                say "You have maxxed out your SlapbirdAPM plan, please upgrade to continue, or wait 30 days.";
                $.lockout = True;
                $.last_lockout = DateTime.now().Instant * 1_000;
            }
            elsif ($r.status != 201) {
                say "Got weird response from SlapbirdAPM? Is it down? " ~ $r.status;
            }
        }
    }

    @middleware.push(sub ($request, $response, &next) {
        my ($start_time, $f) = DateTime.now().Instant.to-posix;
        $response.stash<slapbird_start_time> = $start_time * 1_000;
        $response.stash<slapbird_request> = $request;
        &next();
    });

    @advice.push(sub ($response) {
        if ($.lockout) {
            my $curr = DateTime.now().Instant * 1_000;

            if ($curr - $.last_lockout > 3_600_000) {
                $.lockout = False;
            }
        }

        if (!$.lockout) {
            my ($end_time, $f) = DateTime.now().Instant.to-posix;
            $.channel.send: %(
                request => $response.stash<slapbird_request>,
                response => $response,
                start_time => $response.stash<slapbird_start_time>,
                end_time => $end_time * 1_000,
                error => $response.stash<error>
            );
        }

        return $response;
    });
}
