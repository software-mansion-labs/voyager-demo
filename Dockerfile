# Two-stage build: compile a release with the full toolchain, ship it on a bare
# Debian image. Elixir/OTP versions track .tool-versions.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=bookworm-20260623-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.setup
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM debian:${DEBIAN_VERSION}

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd --create-home app && mkdir -p /var/lib/station && chown app:app /app /var/lib/station
USER app

COPY --from=builder --chown=app:app /app/_build/prod/rel/station ./

CMD ["/app/bin/server"]
