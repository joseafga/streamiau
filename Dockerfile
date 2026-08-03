# Build stage
FROM crystallang/crystal:v1.20.3-alpine-build AS build-image
WORKDIR /app
COPY . .
RUN shards install --production
RUN mkdir /app/bin
RUN crystal build src/streamiau.cr -o bin/streamiau --release --no-debug

# Production stage
FROM alpine:latest AS runtime-image
WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata pcre2 gc libgcc libevent openssl yaml readline
COPY --from=build-image /app/bin/streamiau /app/bin/streamiau
EXPOSE 3000
CMD ["/app/bin/streamiau"]
