#!/bin/sh
# One-time Railway project setup. Run once after `railway login`.
# Requires: Railway CLI (brew install railway)
set -e

echo "==> Initializing Railway project..."
railway init --name wizard-kittenz

echo ""
echo "==> Add a Postgres database service in the Railway dashboard:"
echo "    https://railway.com/new  →  New Service → Database → PostgreSQL"
echo ""
echo "    Once added, come back and press Enter to continue."
read -r _

echo ""
echo "==> Setting production environment variables..."
echo "    (These are stored in Railway only — never committed to git.)"
echo ""

printf "NAKAMA_SERVER_KEY (strong random string): "
read -r server_key
railway variables set "NAKAMA_SERVER_KEY=$server_key"

printf "NAKAMA_HTTP_KEY (strong random string): "
read -r http_key
railway variables set "NAKAMA_HTTP_KEY=$http_key"

printf "NAKAMA_CONSOLE_PASSWORD (admin console password): "
read -r console_password
railway variables set "NAKAMA_CONSOLE_PASSWORD=$console_password"

railway variables set "NAKAMA_CONSOLE_USER=admin"

echo ""
echo "==> All variables set. Deploy with: make deploy"
echo "    Then grab the public URL with: railway domain"
