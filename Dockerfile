# The Hex team's image for exactly the Elixir and OTP patch CI runs (the
# 2026-09-24 runtime hotfix), pinned by tag and digest (ADR-0045 §2). The
# maintenance lane moves it with CI (Dependabot ignores it, see
# .github/dependabot.yml), and ci_test pins the parity.
FROM hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104@sha256:ecb921d948390b863c35002bbbba1f238878574d661559807470d8a119913c19

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
