# The booth image. Two stages: one with a full Elixir toolchain that builds the
# release, one with nothing but Debian and the release itself.
#
# The versions are pinned to .tool-versions, and the runtime is the same Debian
# release as the builder - a release carries compiled NIFs and linked OpenSSL,
# so mixing distributions here is how a container builds on a laptop and then
# refuses to start on a box in another country.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Dependencies first and on their own, so editing a LiveView does not refetch
# and recompile hex on every build.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# mix station.release is assets.deploy plus the release: compile, tailwind,
# esbuild, digest, then the release itself. The order matters - see mix.exs.
COPY rel rel
RUN mix station.release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

# The release runs as nobody, and the leaderboard lives on a volume mounted at
# /var/lib/station - the one file that has to survive a redeploy.
RUN chown nobody /app
USER nobody

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/station ./

CMD ["/app/bin/server"]
