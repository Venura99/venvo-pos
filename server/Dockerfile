# Venvo POS API.
#
# Build from the REPOSITORY ROOT, not from this directory, because the server
# depends on ../packages/venvo_core by path:
#
#   docker build -f server/Dockerfile -t venvo-pos-api .
#
# The result is a single native executable on a slim Debian base — no Dart SDK
# in the shipped image, and nothing to install on the host but Docker.

# The web app, built once and served by the API from the same address.
# Pinned to the Flutter release the project is developed and tested on.
FROM ghcr.io/cirruslabs/flutter:3.47.9 AS web

WORKDIR /src
COPY packages/venvo_core/ packages/venvo_core/
COPY server/ server/
COPY pubspec.yaml pubspec.lock analysis_options.yaml ./
COPY lib/ lib/
COPY web/ web/
RUN flutter pub get && flutter build web --release --no-wasm-dry-run

# ---------------------------------------------------------------------------

FROM dart:stable AS build

WORKDIR /src

# Pubspecs and lockfiles first, so that dependency resolution is cached in its
# own layer and a source change does not re-resolve the world.
COPY packages/venvo_core/pubspec.yaml packages/venvo_core/pubspec.lock packages/venvo_core/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get

# Then the source.
COPY packages/venvo_core/ packages/venvo_core/
COPY server/ server/

# --offline proves the lockfiles above were complete: if a dependency were
# missing the build fails here rather than quietly reaching the network and
# producing an image nobody can reproduce.
RUN cd server && dart pub get --offline \
    && dart compile exe bin/server.dart -o /venvo-pos-api

# ---------------------------------------------------------------------------

FROM debian:stable-slim

# libsqlite3-0 is the database engine. ca-certificates is not needed by the
# API itself but is needed by anything it is later asked to talk to over TLS,
# and costs almost nothing.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

# Runs as a normal user. A process that only needs to read its own binary and
# write one directory has no business being root.
RUN useradd --system --create-home --uid 10001 venvo
COPY --from=build /venvo-pos-api /usr/local/bin/venvo-pos-api
COPY --from=web /src/build/web /usr/share/venvo-pos/web

# The business's data. Mount a volume here — everything that matters lives in
# this one directory, which is also what makes a backup a single archive.
# No VOLUME instruction: Railway refuses Dockerfiles that declare one, and
# docker-compose.yml / Railway each mount their own volume at this path.
RUN mkdir -p /var/lib/venvo-pos && chown venvo:venvo /var/lib/venvo-pos

USER venvo
# TZ matters: "remind N days before the cheque date" and "today" are worked
# out in local time, and the business runs on Sri Lankan time.
ENV VENVO_DATA_DIR=/var/lib/venvo-pos \
    VENVO_WEB_DIR=/usr/share/venvo-pos/web \
    TZ=Asia/Colombo \
    VENVO_PORT=8080 \
    VENVO_BIND_ADDRESS=any

EXPOSE 8080

# VENVO_BIND_ADDRESS is "any" here because inside a container the only way to
# be reachable is to bind every interface. That is safe *because* the
# container is published to a reverse proxy rather than to the internet — see
# docker-compose.yml, which does not publish this port to the host at all.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/venvo-pos-api", "--health-check"]

ENTRYPOINT ["/usr/local/bin/venvo-pos-api"]
