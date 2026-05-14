# Wizard Kittenz

A Godot 4 mobile dungeon-crawler with real-time co-op multiplayer via Nakama.

## Prerequisites

| Tool | Install |
|------|---------|
| Godot 4.6 | [godotengine.org](https://godotengine.org/download) |
| Docker Desktop | [docker.com](https://www.docker.com/products/docker-desktop) |
| flyctl | `brew install flyctl` |
| postgresql-client | `brew install libpq` |
| Android SDK | Via Godot Editor → Editor Settings → Export → Android |

## Local development

### 1. Start the local Nakama server

```bash
make server-start
```

This runs Nakama + Postgres via Docker Compose. The server is available at `http://localhost:7350`. The Nakama console is at `http://localhost:7349` (admin / password).

To stop:

```bash
make server-stop
```

### 2. Configure the client for local

Create `nakama.env` in the project root (gitignored):

```
NAKAMA_HOST=localhost
NAKAMA_PORT=7350
NAKAMA_SERVER_KEY=localdev_server_key
NAKAMA_SCHEME=http
```

The client reads this file at startup. Without it, the client defaults to the production server.

### 3. Open the project in Godot

Open `project.godot` in Godot 4.6. Run from the editor or export to Android (see Export below).

### 4. Run tests

Tests use the [GUT](https://github.com/bitwes/Gut) framework. Run from the Godot editor via the GUT panel, or configure the GUT runner to execute `tests/unit/`.

## Deploying to production

### First-time setup (run once)

```bash
fly auth login
make fly-init
```

`fly-init` creates the Fly.io app, provisions a Postgres cluster, attaches it, and prompts for production secrets (`NAKAMA_SERVER_KEY`, `NAKAMA_HTTP_KEY`, `NAKAMA_CONSOLE_PASSWORD`). Secrets are stored in Fly.io only and are never committed to git.

### Deploy

```bash
make deploy
```

This builds the Docker image and deploys Nakama to `https://wizard-kittenz.fly.dev`.

After deploying, confirm only one machine is running:

```bash
fly scale show --app wizard-kittenz
```

If more than one machine is listed, scale back down (see the note below on why this matters).

```bash
fly scale count 1 --app wizard-kittenz
```

### Database sync

Push your local database to production (overwrites remote):

```bash
make db-push
```

Pull the production database to local (overwrites local):

```bash
make db-pull
```

## Android export

1. In Godot: Project → Export → Android
2. Set your keystore path and credentials in the export dialog
3. Export as `.aab` for Play Store submission or `.apk` for direct install
4. Version code and version name live in `export_presets.cfg` — bump `version/code` by 1 and update `version/name` before each Play Store release

## Infrastructure note: single Nakama instance

**`fly.toml` is intentionally configured to run exactly one Nakama machine.**

```toml
auto_stop_machines = false
auto_start_machines = false   # ← prevents Fly from spinning up a second machine
min_machines_running = 1
```

### Why

Nakama stores relayed match state in memory on the node that created the match. When two players connect, Fly.io's load balancer can route their traffic to different machines. If that happens:

- The host creates a match on Machine A
- The joiner's room-lookup REST call hits Machine B
- Machine B has no match records → "Room not found"

Setting `auto_start_machines = false` prevents Fly from ever starting a second machine, keeping all match state on a single node.

### What this means for scale

A single Nakama node on the current VM (`shared-cpu-1x`, 512 MB) can comfortably handle hundreds of concurrent connections. For an indie mobile game this is sufficient well into a healthy player base.

If the game grows to a point where one instance is a bottleneck:

1. **Scale up vertically first** — `fly scale vm performance-2x` gives more headroom with no code changes
2. **True horizontal scaling** requires replacing in-memory match listing (`list_matches_async`) with a database-backed room registry, likely implemented as a Nakama server-side module (TypeScript/Lua). This is a non-trivial architectural change and is not needed until vertical scaling is exhausted

Do not set `auto_start_machines = true` without first implementing a shared room registry.

## Project structure

```
addons/         Nakama GDScript SDK
android/        Android build templates and Gradle config
assets/         Art, audio, fonts
docs/           Design notes and issue tracking docs
scenes/         Godot scenes (.tscn)
scripts/        GDScript source
server/         Fly.io setup scripts
tests/unit/     GUT unit tests
docker-compose.yml  Local Nakama + Postgres
fly.toml        Fly.io deployment config
nakama-config.yml   Nakama server config (shared local + prod)
export_presets.cfg  Godot Android export settings
```
