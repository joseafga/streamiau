# Build stage
FROM crystallang/crystal:v1.20.3-alpine-build AS build-image
WORKDIR /app
COPY . .
RUN shards install --production
RUN crystal build src/streamiau.cr -o streamiau --release --no-debug

# Production stage
FROM alpine:latest AS runtime-image
WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata pcre2 gc libgcc libevent openssl yaml readline yt-dlp
COPY --from=build-image /app/streamiau /usr/local/bin/streamiau
COPY --from=build-image /app/public /app/public
EXPOSE 3000
CMD ["/usr/local/bin/streamiau"]
