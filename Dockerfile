# syntax=docker/dockerfile:1.7
FROM ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine

WORKDIR /app

COPY gleam.toml manifest.toml ./
RUN gleam deps download

COPY src ./src
COPY priv ./priv

RUN gleam export erlang-shipment

WORKDIR /app/build/erlang-shipment

ENV PORT=8080
ENV HOST=0.0.0.0
EXPOSE 8080

CMD ["./entrypoint.sh", "run"]
