# Wizard Kittenz — server operations
# Requires: flyctl (brew install flyctl), Docker, postgresql-client (brew install libpq)

FLY_APP     := wizard-kittenz
FLY_PG_APP  := wizard-kittenz-db
LOCAL_DB_URL := postgresql://postgres:localdev@localhost:5432/nakama
PROXY_PORT  := 15432

.PHONY: server-start server-stop fly-init deploy db-push db-pull build-module

# ── Local dev ──────────────────────────────────────────────────────────────────

build-module:
	mkdir -p server/dist
	cd server && npm init -y && npm install @heroiclabs/nakama-runtime && npx esbuild rooms.ts --bundle --platform=node --target=es2020 --outfile=dist/rooms.js

server-start: build-module
	docker compose up -d

server-stop:
	docker compose down

# ── Fly.io setup (run once) ────────────────────────────────────────────────────

fly-init:
	@chmod +x server/fly-setup.sh && sh server/fly-setup.sh

# ── Deploy ─────────────────────────────────────────────────────────────────────

deploy:
	fly deploy -a $(FLY_APP)

# ── Database sync ──────────────────────────────────────────────────────────────
# Both targets proxy Fly's private Postgres to localhost:$(PROXY_PORT),
# then use standard pg_dump / psql to move data.

# Push local Postgres → Fly (overwrites remote data)
db-push:
	@echo "==> Opening proxy to Fly Postgres on localhost:$(PROXY_PORT)..."
	fly proxy $(PROXY_PORT):5432 -a $(FLY_PG_APP) &
	@sleep 3
	@echo "==> Pushing local DB to Fly..."
	@FLY_DB=$$(fly ssh console -a $(FLY_APP) -C 'printenv DATABASE_URL' 2>/dev/null | tr -d '\r\n') && \
	  PROXY_URL=$$(echo "$$FLY_DB" | sed 's|@[^:]*:5432|@localhost:$(PROXY_PORT)|') && \
	  pg_dump --no-owner --no-privileges "$(LOCAL_DB_URL)" | psql "$$PROXY_URL"
	@pkill -f "fly proxy $(PROXY_PORT)" || true
	@echo "==> Done."

# Pull Fly Postgres → local (overwrites local data)
db-pull:
	@echo "==> Opening proxy to Fly Postgres on localhost:$(PROXY_PORT)..."
	fly proxy $(PROXY_PORT):5432 -a $(FLY_PG_APP) &
	@sleep 3
	@echo "==> Pulling Fly DB to local..."
	@FLY_DB=$$(fly ssh console -a $(FLY_APP) -C 'printenv DATABASE_URL' 2>/dev/null | tr -d '\r\n') && \
	  PROXY_URL=$$(echo "$$FLY_DB" | sed 's|@[^:]*:5432|@localhost:$(PROXY_PORT)|') && \
	  pg_dump --no-owner --no-privileges "$$PROXY_URL" | psql "$(LOCAL_DB_URL)"
	@pkill -f "fly proxy $(PROXY_PORT)" || true
	@echo "==> Done."
