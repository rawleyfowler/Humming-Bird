use v6.d;

unit role Humming-Bird::Backend;

has Int:D $.port = 8080;
has Int:D $.timeout is required;

method listen(&handler) {
    die "{ self.^name } does not properly implement Humming-Bird::Backend.";
}
