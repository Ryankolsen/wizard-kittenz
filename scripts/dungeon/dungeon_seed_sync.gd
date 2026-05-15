class_name DungeonSeedSync
extends RefCounted

# Per-match agreed dungeon seed. Host picks a fresh non-negative seed at
# match start (host_mint), the wire layer (#14, HITL) carries that seed
# to every remote client on the "match started" packet, each remote
# applies it via apply_remote_seed. All clients then call
# DungeonGenerator.generate(seed_sync.current_seed()) and the procedural
# layout — room count, connections, enemy kinds, power-up types —
# converges across the party.
#
# Closes the recurring "all clients must converge on the same dungeon
# layout" gap that AC#1 of #17 ("2-4 players can crawl the same
# dungeon simultaneously") implies. Without seed sync, every client's
# DungeonGenerator.generate() draws its own seed via rng.randomize() and
# the layouts diverge — remote kittens would spawn in rooms the local
# client has never rendered, and RoomSpawnPlanner / RoomClearWatcher
# would key off enemy_ids that other clients don't have.
#
# Pure data — no I/O, no scene tree. The wire layer is the owner; this
# helper just stores the agreed seed and pins the host/remote-only
# contracts (host mints, remote applies, neither overwrites an
# already-agreed seed).
#
# Sentinel: NOT_AGREED = -1 mirrors DungeonGenerator's "randomize"
# sentinel (seed < 0 → randomize, seed >= 0 → deterministic). Using -1
# (not 0) means seed 0 is a valid agreed seed, not "not agreed yet" —
# matches DungeonGenerator's contract that 0 is a real deterministic
# seed.
#
# Idempotency / defensiveness:
#   - host_mint() called twice returns the existing seed without
#     re-minting (re-mint after broadcast would desync clients that
#     already received the first seed).
#   - apply_remote_seed(seed) on an already-agreed sync returns false
#     (re-broadcast from a flaky network is a no-op, not a desync).
#   - apply_remote_seed(negative) returns false (defensive against
#     wire-payload corruption that flips a sign bit).
#   - reset() clears state so the same instance can be reused for the
#     next match without re-construction.
#
# What this does NOT do:
#   - Construct the dungeon. The caller passes current_seed() into
#     DungeonGenerator.generate. Keeping this helper free of generator
#     references means a future generator swap (e.g. a hand-authored
#     dungeon catalog) doesn't touch the seed-sync contract.
#   - Validate that host and remote actually agreed on the same seed.
#     If the wire layer corrupts the seed in transit, the divergence
#     surfaces immediately when the two dungeons differ; defending
#     against transit corruption is the wire layer's job.

signal seed_agreed(seed: int)

const NOT_AGREED: int = -1

var _seed: int = NOT_AGREED

# Host-side: mints a fresh non-negative seed and stores it. Idempotent
# — second call returns the existing seed without re-minting and
# without re-emitting seed_agreed (so a host UI that double-fires
# "start match" doesn't desync remote clients that already received
# the first seed).
#
# seed_override: when >= 0, uses that seed instead of drawing from RNG.
# Useful for deterministic test paths and a future "replay this
# specific dungeon" QA hook. Negative override (the default) draws a
# fresh random seed via RandomNumberGenerator.randomize.
#
# randi() returns a signed 32-bit int that can be negative. We mask the
# sign bit so the result is always in [0, INT32_MAX] — never the
# NOT_AGREED sentinel and never something that DungeonGenerator's
# `seed < 0 → randomize` branch would mis-route.
func host_mint(seed_override: int = -1) -> int:
	if _seed >= 0:
		return _seed
	if seed_override >= 0:
		_seed = seed_override
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_seed = rng.randi() & 0x7FFFFFFF
	seed_agreed.emit(_seed)
	return _seed

# Remote-side: stores the host's seed received from the wire layer.
# Returns true on a fresh apply, false on:
#   - negative seed (defensive — wire payload corruption / sign-bit flip)
#   - already agreed (idempotent — re-broadcast from a flaky network
#     is a no-op rather than a desync)
func apply_remote_seed(seed: int) -> bool:
	if seed < 0:
		return false
	if _seed >= 0:
		return false
	_seed = seed
	seed_agreed.emit(_seed)
	return true

func is_agreed() -> bool:
	return _seed >= 0

func current_seed() -> int:
	return _seed

# Clears the agreed seed so the same instance can be reused for the
# next match. The future match orchestrator calls reset() between
# runs (e.g. on "play again" from the summary screen) to avoid
# allocating a fresh sync per match.
func reset() -> void:
	_seed = NOT_AGREED
