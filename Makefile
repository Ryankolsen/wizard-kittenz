# Wizard Kittenz — server operations
# Requires: Railway CLI (brew install railway), Docker, postgresql-client (brew install libpq)

LOCAL_DB_URL := postgresql://postgres:localdev@localhost:5432/nakama

.PHONY: server-start server-stop railway-init deploy db-push db-pull

# ── Local dev ──────────────────────────────────────────────────────────────────

server-start:
	docker compose up -d

server-stop:
	docker compose down

# ── Railway setup (run once) ───────────────────────────────────────────────────

railway-init:
	@chmod +x server/railway-setup.sh && sh server/railway-setup.sh

# ── Deploy ─────────────────────────────────────────────────────────────────────

deploy:
	railway up --detach

# ── Database sync ──────────────────────────────────────────────────────────────

# Push local Postgres → Railway (overwrites remote data)
db-push:
	@echo "==> Pushing local DB to Railway..."
	pg_dump --no-owner --no-privileges "$(LOCAL_DB_URL)" \
	  | railway run psql "$$DATABASE_URL"
	@echo "==> Done."

# Pull Railway Postgres → local (overwrites local data)
db-pull:
	@echo "==> Pulling Railway DB to local..."
	railway run sh -c 'pg_dump --no-owner --no-privileges "$$DATABASE_URL"' \
	  | psql "$(LOCAL_DB_URL)"
	@echo "==> Done."
