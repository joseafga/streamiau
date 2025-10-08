FROM lukemathwalker/cargo-chef:latest-rust-1-trixie AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY . .
RUN cargo build --release --bin stream-api

# We do not need the Rust toolchain to run the binary!
FROM debian:trixie-slim AS runtime
RUN apt-get update && apt-get install -y python3-pip
RUN pip install --break-system-packages -U yt-dlp

WORKDIR /app
COPY --from=builder /app/target/release/stream-api /usr/local/bin
COPY ./pages /app/pages
ENTRYPOINT ["/usr/local/bin/stream-api"]
