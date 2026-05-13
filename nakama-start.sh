#!/bin/sh
set -e

# Railway provides DATABASE_URL as postgresql://user:pass@host:port/db
# Nakama expects: user:pass@host:port/db
DB_ADDR="${DATABASE_URL#postgresql://}"
DB_ADDR="${DB_ADDR#postgres://}"

until /nakama/nakama migrate up --database.address "$DB_ADDR"; do
  echo "Database not ready, retrying in 5s..."
  sleep 5
done

exec /nakama/nakama \
  --name wizard-kittenz \
  --database.address "$DB_ADDR" \
  --socket.server_key "${NAKAMA_SERVER_KEY}" \
  --runtime.http_key "${NAKAMA_HTTP_KEY}" \
  --console.username "${NAKAMA_CONSOLE_USER:-admin}" \
  --console.password "${NAKAMA_CONSOLE_PASSWORD}"
