# syntax=docker/dockerfile:1.7
#
# Single-stage build. Using the Gleam image as the runtime too guarantees the
# Erlang/OTP version matches between compile and run — a previous multi-stage
# attempt with `erlang:27-alpine` failed at boot (undef on cantrip@@main),
# almost certainly because the Gleam image bundles a newer OTP than 27.

FROM ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine

WORKDIR /app

# Cache deps in their own layer
COPY gleam.toml manifest.toml ./
RUN gleam deps download

# Source + runtime assets
COPY src ./src
COPY priv ./priv

# Builds /app/build/erlang-shipment/ with entrypoint.sh
RUN gleam export erlang-shipment

WORKDIR /app/build/erlang-shipment

# Render injects PORT; this is just a sensible local default
ENV PORT=8080
ENV HOST=0.0.0.0
EXPOSE 8080

CMD ["./entrypoint.sh", "run"]
