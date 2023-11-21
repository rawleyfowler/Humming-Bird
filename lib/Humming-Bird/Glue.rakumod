use HTTP::Status;
use MIME::Types;
use URI::Encode;
use DateTime::Format::RFC2822;
use JSON::Fast;

unit module Humming-Bird::Glue;

my constant $rn = Buf.new("\r\n".encode);
my constant $rnrn = Buf.new("\r\n\r\n".encode);

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

class HTTPAction {
    has $.context-id;
    has %.headers;
    has %.cookies;
    has %.stash;
    has Buf:D $.body is rw = Buf.new;

    # Find a header in the action, return (Any) if not found
    multi method header(Str:D $name --> Str) {
        my $lc-name = $name.lc;
        return Str without %.headers{$lc-name};
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
    subset Content where * ~~ Buf:D | Map:D | List:D;
    method content(--> Content:D) {

        state $prev-body = $.body;
        
        return $!content if $!content && ($prev-body eqv $.body);
        return $!content = Map.new unless self.header('Content-Type');

        {
            CATCH {
                default {
                    warn "Encountered Error: $_;\n Failed parsing a body of type { self.header('Content-Type') }"; return ($!content = Map.new)
                }
            }

            if self.header('Content-Type').ends-with: 'json' {
                $!content = from-json($.body.decode).Map;
            } elsif self.header('Content-Type').ends-with: 'urlencoded' {
                $!content = parse-urlencoded($.body.decode).Map;
            } elsif self.header('Content-Type').starts-with: 'multipart/form-data' {
                # Multi-part parser based on: https://github.com/croservices/cro-http/blob/master/lib/Cro/HTTP/BodyParsers.pm6
                my $boundary = self.header('Content-Type') ~~ /.*'boundary="' <(.*)> '"' ';'?/;

                # For some reason there is no standard for quotes or no quotes.
                $boundary //= self.header('Content-Type') ~~ /.*'boundary=' <(.*)> ';'?/;

                $boundary .= Str with $boundary;

                without $boundary {
                    die "Missing boundary parameter in for 'multipart/form-data'";
                }

                my $payload = $.body.decode('latin-1');

                my $dd-boundary = "--$boundary";
                my $start = $payload.index($dd-boundary);
                without $start {
                    die "Could not find starting boundary of multipart/form-data";
                }

                # Extract all the parts.
                my $search = "\r\n$dd-boundary";
                $payload .= substr($start + $dd-boundary.chars);
                my @part-strs;
                loop {
                    last if $payload.starts-with('--');
                    my $end-boundary-line = $payload.index("\r\n");
                    without $end-boundary-line {
                        die "Missing line terminator after multipart/form-data boundary";
                    }
                    if $end-boundary-line != 0 {
                        if $payload.substr(0, $end-boundary-line) !~~ /\h+/ {
                            die "Unexpected text after multpart/form-data boundary " ~
                            "('$end-boundary-line')";
                        }
                    }

                    my $next-boundary = $payload.index($search);
                    without $next-boundary {
                        die "Unable to find boundary after part in multipart/form-data";
                    }
                    my $start = $end-boundary-line + 1;
                    @part-strs.push($payload.substr($start, $next-boundary - $start));
                    $payload .= substr($next-boundary + $search.chars);
                }

                my %parts;
                for @part-strs -> $part {
                    my ($header, $body-str) = $part.split("\r\n\r\n", 2);
                    my %headers = decode-headers($header.split("\r\n", :skip-empty));
                    with %headers<content-disposition> {
                        my $param-start = .index(';');
                        my $parameters = $param-start ?? .substr($param-start) !! Str;
                        without $parameters {
                            die "Missing content-disposition parameters in multipart/form-data part";
                        }

                        my $name = $parameters.match(/'name="'<(<[a..z A..Z 0..9 \- _ : \.]>+)>'";'?.*/).Str;
                        my $filename-param = $parameters.match(/.*'filename="'<(<[a..z A..Z 0..9 \- _ : \.]>+)>'";'?.*/);
                        my $filename = $filename-param ?? $filename-param.Str !! Str;
                        %parts{$name} = {
                            :%headers,
                            $filename ?? :$filename !! (),
                            body => Buf.new($body-str.encode('latin-1'))
                        };
                    }
                    else {
                        die "Missing content-disposition header in multipart/form-data part";
                    }
                }

                $!content := %parts;
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

    multi submethod decode(Str:D $payload --> Request:D) {
        return Request.decode(Buf.new($payload.encode));
    }
    multi submethod decode(Buf:D $payload --> Request:D) {
        my $binary-str = $payload.decode('latin-1');
        my $idx = 0;

        loop {
            $idx++;
            last if (($payload[$idx] == $rn[0]
                      && $payload[$idx + 1] == $rn[1])
                     || $idx > ($payload.bytes + 1));
        } 
        my ($method_raw, $path, $version) = $payload.subbuf(0, $idx).decode.chomp.split(/\s/, 3, :skip-empty);

        my $method = http-method-of-str($method_raw);

        # Find query params
        my %query;
        if uri_decode_component($path) ~~ m:g /\w+"="(<-[&]>+)/ {
            %query = Map.new($<>.map({ .split('=', 2, :skip-empty) }).flat);
            $path = $path.split('?', 2)[0];
        }

        $idx += 2;
        my $header-marker = $idx;
        loop {
            $idx++;
            last if (($payload[$idx] == $rnrn[0]
                      && $payload[$idx + 1] == $rnrn[1]
                      && $payload[$idx + 2] == $rnrn[2]
                      && $payload[$idx + 3] == $rnrn[3])
                     || $idx > ($payload.bytes + 3));
        }

        my $header-section = $payload.subbuf($header-marker, $idx);

        # Lose the request line and parse an assoc list of headers.
        my %headers = decode-headers($header-section.decode('latin-1').split("\r\n", :skip-empty));

        $idx += 4;
        # Body should only exist if either of these headers are present.
        my $body;
        with %headers<content-length> {
            if ($idx + 1 < $payload.bytes) {
                my $len = +%headers<content-length>;
                $body = Buf.new: $payload[$idx..($payload.bytes - 1)].Slip;
            }
        }

        $body //= Buf.new;

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
        self.write(Buf.new($body.encode), $content-type);
        self;
    }
    multi method write(Failure $body, Str:D $content-type = 'text/plain', --> Response:D) {
        self.write(Buf.new(($body.Str ~ "\n" ~ $body.backtrace).encode), $content-type);
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
        my $body-size = $.body.bytes;

        if $body-size > 0 && self.header('Content-Type') && self.header('Content-Type') !~~ /.*'octet-stream'.*/ {
            %.headers<content-type> ~= '; charset=utf-8';
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

        return Buf.new($out.encode).append: $.body if $with-body;
        return $out;
    }
}
