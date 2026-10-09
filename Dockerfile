# The Hex team's image for exactly the Elixir and OTP patch CI runs (the
# 2026-09-24 runtime hotfix), pinned by tag and digest (ADR-0045 §2). The
# maintenance lane moves it with CI (Dependabot ignores it, see
# .github/dependabot.yml), and ci_test pins the parity.
FROM hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005@sha256:9afc7f7fb2e21eb973c21c917b631b56d558dc00cc970a60fce81d2d70825838

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
