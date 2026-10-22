# syntax=docker/dockerfile:1
# check=error=true

# SignalCraft application image (design specifications/02). One image runs the
# web, media, worker and migrate roles. Pin RUBY_VERSION to an exact release
# and the base image by digest when releasing.
#
#   docker build -t signalcraft .
#
# The application lives at /var/www/signalcraft, with the operator-provided
# directories /var/www/signalcraft/plugins (addon gems, baked in at build) and
# /var/www/signalcraft/config (signalcraft.yml and secrets/, mounted at runtime).

ARG RUBY_VERSION=3.4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /var/www/signalcraft

# Runtime packages: PostgreSQL client library and jemalloc. No FFmpeg or image
# tools: media processing happens only in the FFmpeg service.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libpq5 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SIGNALCRAFT_ROOT="/var/www/signalcraft"

# Build stage: gems (including addon gems from plugins/) and assets.
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Addons are part of the dependency set, so they are copied before bundling.
COPY Gemfile Gemfile.lock ./
COPY plugins ./plugins
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Assets are compiled with throwaway configuration that is removed afterwards;
# real configuration is mounted at runtime.
RUN RAILS_ENV=development ./bin/dev-config && \
    ./bin/rails assets:precompile && \
    rm -f config/signalcraft.yml && find config/secrets -type f ! -name README.md -delete

# Fingerprint the addon directory; bin/docker-entrypoint refuses to start if a
# mounted plugins directory differs from this build.
RUN ./bin/plugin-lock

# Final stage: non-root, read-only-root friendly.
FROM base

RUN groupadd --system --gid 10001 signalcraft && \
    useradd signalcraft --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /var/www/signalcraft /var/www/signalcraft

# Only tmp/ and log/ are written to at runtime; mount them as tmpfs when the
# root filesystem is read-only.
RUN mkdir -p tmp/pids log && chown -R 10001:10001 tmp log

USER 10001:10001

ENTRYPOINT ["/var/www/signalcraft/bin/docker-entrypoint"]

# Roles (see deploy/compose.example.yml):
#   web:     ./bin/rails server -b 0.0.0.0 -p 3000   (default)
#   media:   ./bin/rails server -b 0.0.0.0 -p 3001 -C config/puma_media.rb
#   worker:  ./bin/jobs
#   migrate: migrate
EXPOSE 3000 3001
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
