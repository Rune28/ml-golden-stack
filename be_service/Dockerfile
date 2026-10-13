# be_service: static-ish Rust binary on distroless.
# cargo-chef builds the dependencies as their own layer, so a code change
# rebuilds only the crate itself. Builder and runtime are both Debian 13
# (trixie), so the binary links against the same glibc it runs with.

FROM lukemathwalker/cargo-chef:0.1.78-rust-1.99.0-slim-trixie AS chef
# protoc and the well-known .proto files: the Temporal SDK compiles its
# protobuf definitions at build time.
RUN apt-get update && apt-get install -y --no-install-recommends protobuf-compiler libprotobuf-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS build
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
RUN cargo build --release --locked

# libc, libgcc and CA certificates (rustls checks the MNIST mirror against
# the system store); no shell, runs as uid 65532.
FROM gcr.io/distroless/cc-debian13:nonroot
COPY --from=build /app/target/release/be_service /be_service
EXPOSE 8080
ENTRYPOINT ["/be_service"]
