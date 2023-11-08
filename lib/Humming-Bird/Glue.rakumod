use HTTP::Status;
use MIME::Types;
use URI::Encode;
use DateTime::Format::RFC2822;

unit module Humming-Bird::Glue;

# Mime type parser from MIME::Types
my constant $mime = MIME::Types.new;

enum HTTPMethod is export <GET POST PUT PATCH DELETE HEAD OPTIONS>;

# Converts a string of headers "KEY: VALUE\r\nKEY: VALUE\r\n..." to a map of headers.
my sub decode-headers(@header_block --> Map:D) {
    Map.new(@header_block.map(*.trim.split(': ', 2, :skip-empty).map(*.trim)).map({ [@^a[0].lc, @^a[1]] }).flat);
}

sub trim-utc-for-gmt(Str:D $utc --> Str:D) { $utc.subst(/"+0000"/, 'GMT') }
sub now-rfc2822(--> Str:D) {
    trim-utc-for-gmt: DateTime.now(formatter => DateTime::Format::RFC2822.new()).utc.Str;
}

# Convert a string to HTTP method, defaults to GET
sub http-method-of-str(Str:D $method --> HTTPMethod:D) {
    given $method.lc {
        when 'get' { GET }
        when 'post' { POST; }
        when 'put' { PUT }
        when 'patch' { PATCH }
        when 'delete' { DELETE }
        when 'head' { HEAD }
        default { GET }
    }
}

my subset SameSite of Str where 'Strict' | 'Lax';
class Cookie is export {
    has Str $.name;
    has Str $.value;
    has DateTime $.expires;
    has Str $.domain;
    has Str $.path where { .starts-with('/') orelse .throw } = '/';
    has SameSite $.same-site = 'Strict';
    has Bool $.http-only = True;
    has Bool $.secure = False;

    method encode(--> Str:D) {
        my $expires = ~trim-utc-for-gmt($.expires.clone(formatter => DateTime::Format::RFC2822.new()).utc.Str);
        ("$.name=$.value", "Expires=$expires", "SameSite=$.same-site", "Path=$.path", $.http-only ?? 'HttpOnly' !! '', $.secure ?? 'Secure' !! '', $.domain // '')
        .grep({ .chars })
        .join('; ');
    }

    submethod decode(Str:D $cookie-string) { # We decode "simple" cookies only, since they come from the requests
        Map.new: $cookie-string.split(/\s/, 2, :skip-empty)
                  .map(*.split('=', 2, :skip-empty))
                  .map(-> ($name, $value) { $name => Cookie.new(:$name, :$value) })
                  .flat;
    }
}

my subset Body where * ~~ Buf:D | Str:D;
class HTTPAction {
    has $.context-id;
    has %.headers;
    has %.cookies;
    has %.stash; # The stash is never encoded or decoded. It exists purely for internal talking between middlewares, request handlers, etc.
    has Body:D $.body is rw = "";

    # Find a header in the action, return (Any) if not found
    multi method header(Str:D $name --> Str) {
        my $lc-name = $name.lc;
        return Nil without %.headers{$lc-name};
        %.headers{$lc-name};
    }

    multi method header(Str:D $name, Str:D $value) {
        %.headers{$name.lc} = $value;
        self;
    }

    multi method cookie(Str:D $name --> Cookie) {
        return Nil without %.cookies{$name};
        %.cookies{$name};
    }

    method log(Str:D $message, :$file = $*OUT) {
        $file.print: "[Context: { self.context-id }] | [Time: { DateTime.now }] | $message\n";
        self;
    }
}

my sub parse-urlencoded(Str:D $urlencoded --> Map:D) {
    $urlencoded.split('&', :skip-empty).map(&uri_decode_component)>>.split('=', 2, :skip-empty)>>.map(-> $a, $b { $b.contains(',') ?? slip $a => $b.split(',', :skip-empty) !! slip $a => $b })
    .flat
    .Map;
}

class Request is HTTPAction is export {
    has Str $.path is required;
    has HTTPMethod $.method is required;
    has Str $.version is required;
    has %.params;
    has %.query;
    has $!content;

    # Attempts to parse the body to a Map or return an empty map if we can't decode it
    method content(--> Map:D) {
        use JSON::Fast;

        state $prev-body = $.body;
        
        return $!content if $!content && ($prev-body eqv $.body);
        return $!content = Map.new unless self.header('Content-Type');

        try {
            CATCH {
                default {
                    warn "Encountered Error: $_;\n\n Failed trying to parse a body of type { self.header('Content-Type') }"; return ($!content = Map.new)
                }
            }

            if self.header('Content-Type').ends-with: 'json' {
                $!content = from-json(self.body).Map;
            } elsif self.header('Content-Type').ends-with: 'urlencoded' {
                $!content = parse-urlencoded(self.body);
            }

            return $!content;
        }

        $!content = Map.new;
    }

    method param(Str:D $param --> Str) {
        return Nil without %!params{$param};
        %!params{$param};
    }

    method queries {
        return %!query;
    }

    multi method query {
        return %!query;
    }
    multi method query(Str:D $query_param --> Str) {
        return Nil without %!query{$query_param};
        %!query{$query_param};
    }

    submethod decode(Str:D $raw-request --> Request:D) {
        use URI::Encode;
        # Example: GET /hello.html HTTP/1.1\r\n ~~~ Followed my some headers
        my @lines = $raw-request.lines;
        my ($method_raw, $path, $version) = @lines.head.split(/\s/, :skip-empty);

        my $method = http-method-of-str($method_raw);

        # Find query params
        my %query;
        if uri_decode_component($path) ~~ m:g /\w+"="(<-[&]>+)/ {
            %query = Map.new($<>.map({ .split('=', 2) }).flat);
            $path = $path.split('?', 2)[0];
        }

        # Break the request into the body portion, and the upper headers/request line portion
        my @split_request = $raw-request.split("\r\n\r\n", 2, :skip-empty);
        my $body = "";

        # Lose the request line and parse an assoc list of headers.
        my %headers = decode-headers(@split_request[0].split("\r\n", :skip-empty).skip(1));

        # Body should only exist if either of these headers are present.
        with %headers<content-length> || %headers<transfer-encoding> {
            $body = @split_request[1] || $body;
        }

        # Absolute uris need their path encoded differently.
        without %headers<host> {
            my $abs-uri = $path;
            $path = $abs-uri.match(/^'http' 's'? '://' <[A..Z a..z \w \. \- \_ 0..9]>+ <('/'.*)>? $/).Str;
            %headers<host> = $abs-uri.match(/^'http''s'?'://'(<-[/]>+)'/'?.* $/)[0].Str;
        }

        my %cookies;
        # Parse cookies
        with %headers<cookie> {
            %cookies := Cookie.decode(%headers<cookie>);
        }

        my $context-id = rand.Str.subst('0.', '').substr: 0, 5;

        Request.new(:$path, :$method, :$version, :%query, :$body, :%headers, :%cookies, :$context-id);
    }
}

class Response is HTTPAction is export {
    has HTTP::Status $.status is required;
    has Request:D $.initiator is required handles <context-id>;

    proto method cookie(|) {*}
    multi method cookie(Str:D $name, Cookie:D $value) {
        %.cookies{$name} = $value;
        self;
    }
    multi method cookie(Str:D $name, Str:D $value, DateTime:D $expires) {
        # Default
        my $cookie = Cookie.new(:$name, :$value, :$expires);
        %.cookies{$name} = $cookie;
        self;
    }
    multi method cookie(Str:D $name, Str:D $value, :$expires, :$secure) {
        my $cookie = Cookie.new(:$name, :$value, :$expires, :$secure);
        %.cookies{$name} = $cookie;
        self;        
    }

    proto method status(|) {*}
    multi method status(--> HTTP::Status) { $!status }
    multi method status(Int:D $status --> Response:D) {
        $!status = HTTP::Status($status);
        self;
    }
    multi method status(HTTP::Status:D $status --> Response:D) {
        $!status = $status;
        self;
    }

    # Redirect to a given URI, :$permanent allows for a 308 status code vs a 307
    method redirect(Str:D $to, :$permanent, :$temporary) {
        self.header('Location', $to);
        self.status(303);

        self.status(307) if $temporary;
        self.status(308) if $permanent;
        
        self;
    }

    method html(Str:D $body --> Response:D) {
        $.write($body, 'text/html');
        self;
    }

    # Write a JSON string to the body of the request
    method json(Str:D $body --> Response:D) {
        $.write($body, 'application/json');
        self;
    }

    # Set a file to output.
    method file(Str:D $file --> Response:D) {
        my $text = $file.IO.slurp(:bin);
        my $mime-type = $mime.type($file.IO.extension) // 'text/plain';
        try {
            CATCH {
                $mime-type = 'application/octet-stream' if $mime-type eq 'text/plain';
                return $.blob($text, $mime-type);
            }
            # Decode will fail if it's a binary file
            $.write($text.decode, $mime-type);
        }
        self;
    }

    # Write a blob or buffer
    method blob(Buf:D $body, Str:D $content-type = 'application/octet-stream', --> Response:D) {
        $.body = $body;
        self.header('Content-Type', $content-type);
        self;
    }
    # Alias for blob
    multi method write(Buf:D $body, Str:D $content-type = 'application/octet-stream', --> Response:D) {
        self.blob($body, $content-type);
    }
    # Write a string to the body of the response, optionally provide a content type
    multi method write(Str:D $body, Str:D $content-type = 'text/plain', --> Response:D) {
        $.body = $body;
        self.header('Content-Type', $content-type);
        self;
    }
    multi method write(Failure $body, Str:D $content-type = 'text/plain', --> Response:D) {
        self.write($body.Str ~ "\n" ~ $body.backtrace, $content-type);
        self.status(500);
        self;
    }

    # Set content type of the response
    method content-type(Str:D $type --> Response) {
        self.header('Content-Type', $type);
        self;
    }

    # $with_body is for HEAD requests.
    method encode(Bool:D $with-body = True --> Buf:D) {
        my $out = sprintf("HTTP/1.1 %d $!status\r\n", $!status.code);
        my $body-size = $.body ~~ Buf:D ?? $.body.bytes !! $.body.chars;

        if $body-size > 0 && self.header('Content-Type') && self.header('Content-Type') !~~ /.*'octet-stream'.*/ {
            %.headers<content-type> ~= '; charset=utf8';
        }

        $out ~= sprintf("Content-Length: %d\r\n", $body-size);
        $out ~= sprintf("Date: %s\r\n", now-rfc2822);
        $out ~= "X-Server: Humming-Bird (Raku)\r\n";

        for %.headers.pairs {
            $out ~= sprintf("%s: %s\r\n", .key, .value);
        }

        for %.cookies.values {
            $out ~= sprintf("Set-Cookie: %s\r\n", .encode);
        }

        $out ~= "\r\n";

        do given $.body {
            when Str:D {
                my $resp = $out ~ $.body;
                $resp.encode.Buf if $with-body;
            }

            when Buf:D {
                ($out.encode ~ $.body).Buf if $with-body;
            }
        }
    }
}
