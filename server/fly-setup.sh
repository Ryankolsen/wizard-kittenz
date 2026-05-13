#!/bin/sh
# One-time Fly.io project setup. Run once after `fly auth login`.
# Requires: flyctl (brew install flyctl)
set -e

FLY_APP="wizard-kittenz"
FLY_PG_APP="wizard-kittenz-db"
REGION="ord"

echo "==> Creating Fly.io app..."
fly apps create "$FLY_APP"

echo ""
echo "==> Creating Postgres cluster (this takes ~2 minutes)..."
fly postgres create --name "$FLY_PG_APP" --region "$REGION" --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 1

echo ""
echo "==> Attaching Postgres to app (sets DATABASE_URL automatically)..."
fly postgres attach "$FLY_PG_APP" -a "$FLY_APP"

echo ""
echo "==> Setting production secrets..."
echo "    (Stored in Fly.io only — never committed to git.)"
echo ""

printf "NAKAMA_SERVER_KEY (strong random string): "
read -r server_key
fly secrets set "NAKAMA_SERVER_KEY=$server_key" -a "$FLY_APP"

printf "NAKAMA_HTTP_KEY (strong random string): "
read -r http_key
fly secrets set "NAKAMA_HTTP_KEY=$http_key" -a "$FLY_APP"

printf "NAKAMA_CONSOLE_PASSWORD (admin console password): "
read -r console_password
fly secrets set "NAKAMA_CONSOLE_PASSWORD=$console_password" -a "$FLY_APP"

fly secrets set "NAKAMA_CONSOLE_USER=admin" -a "$FLY_APP"

echo ""
echo "==> All set. Deploy with: make deploy"
echo "    Your public URL will be: https://$FLY_APP.fly.dev"
