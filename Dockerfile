FROM elixir:1.18.3-otp-27

ENV DEBIAN_FRONTEND=noninteractive \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
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

RUN mix local.hex --force && \
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
