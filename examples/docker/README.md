# Docker Example

A simple example of how to use Humming-Bird with Docker.

### How to build
```bash
cd examples/docker
docker build . -t humming-bird-example
docker run -p 8080:8080 -d humming-bird-example
```
