FROM rakudo-star
RUN zef install Humming-Bird
EXPOSE 8080
WORKDIR /docker-example
COPY . .
CMD ["raku", "app.raku"]
