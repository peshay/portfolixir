#!/usr/bin/env sh
# Release entrypoint (ADR-0045 §2, #760): run pending migrations, then hand
# over to the release command (`start` by default). No Mix in this image; the
# migrations run through Portfolixir.Release.
set -eu

echo "Running database migrations..."
/opt/app/bin/portfolixir eval "Portfolixir.Release.migrate()"

echo "Starting Portfolixir..."
exec /opt/app/bin/portfolixir "$@"
