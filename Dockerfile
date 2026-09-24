# The Hex team's image for exactly the Elixir and OTP patch CI runs (the
# 2026-09-24 runtime hotfix), pinned by tag and digest (ADR-0045 §2); the
# Dependabot docker entry keeps both current, and ci_test pins the parity.
FROM hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918@sha256:c5b37bfe39880e010903127ca75a484be0ecf4ef9ee9b3efb5b55d9a0df4944d

ENV DEBIAN_FRONTEND=noninteractive \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    HEX_VERSION=2.4.2 \
    PATH="/opt/mix/bin:${PATH}" \
    APP_HOME=/app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      git \
      inotify-tools \
      libpq-dev \
      postgresql-client \
      wget \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex ${HEX_VERSION} --force && \
    mix local.rebar --force

WORKDIR ${APP_HOME}

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 4000

ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]
CMD ["mix", "phx.server"]
