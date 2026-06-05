# syntax=docker/dockerfile:1.7

# ----- build stage: full Gleam toolchain -----
FROM ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine AS build

WORKDIR /build

# Cache deps in their own layer so source edits don't reinstall them
COPY gleam.toml manifest.toml ./
RUN gleam deps download

# Now bring source + runtime assets
COPY src ./src
COPY priv ./priv

# Produces /build/build/erlang-shipment/ with an entrypoint.sh
RUN gleam export erlang-shipment

# ----- runtime stage: minimal Erlang -----
FROM erlang:27-alpine

WORKDIR /app
COPY --from=build /build/build/erlang-shipment ./

# Render injects PORT; this is just a sensible local default
ENV PORT=8080
EXPOSE 8080

CMD ["./entrypoint.sh", "run"]
