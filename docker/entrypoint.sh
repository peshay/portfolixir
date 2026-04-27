#!/usr/bin/env bash
set -euo pipefail

MIX_ENV="${MIX_ENV:-dev}"
DATABASE_HOST="${DATABASE_HOST:-127.0.0.1}"
DATABASE_PORT="${DATABASE_PORT:-5432}"
DATABASE_USER="${DATABASE_USER:-postgres}"
DATABASE_PASSWORD="${DATABASE_PASSWORD:-postgres}"

if [ "${MIX_ENV}" = "test" ]; then
  DATABASE_NAME="${DATABASE_NAME:-portfolixir_test}"
else
  DATABASE_NAME="${DATABASE_NAME:-portfolixir_dev}"
fi

export DATABASE_HOST
export DATABASE_NAME
export DATABASE_USER
export DATABASE_PASSWORD
export MIX_ENV
export PGPASSWORD="${DATABASE_PASSWORD}"

until pg_isready -h "${DATABASE_HOST}" -p "${DATABASE_PORT}" -U "${DATABASE_USER}" >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL at ${DATABASE_HOST}:${DATABASE_PORT}..."
  sleep 1
done

echo "Installing dependencies..."
mix deps.get

if [ -z "$(psql -h "${DATABASE_HOST}" -p "${DATABASE_PORT}" -U "${DATABASE_USER}" -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}';" | tr -d '[:space:]')" ]; then
  echo "Creating database ${DATABASE_NAME}..."
  mix ecto.create
else
  echo "Database ${DATABASE_NAME} already exists."
fi

echo "Running database migrations..."
mix ecto.migrate

echo "Starting Phoenix..."
exec "$@"
