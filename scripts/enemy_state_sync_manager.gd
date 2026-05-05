class_name EnemyStateSyncManager
extends RefCounted

# Per-enemy authoritative liveness shared across clients. Host owns the
# canonical enemy registry; each death is broadcast as an event that
# every client applies to its local registry, so a kill on host's screen
# ripples to remote clients without ghost enemies hanging around.
#
# Pure data — wire layer (Nakama after #14 lands) calls apply_death
# (enemy_id) when the match packet says "enemy N died". register_enemy
# is called on spawn (host-side) or on the spawn broadcast (remote-side).
# The dungeon graph (#12) gives every spawned enemy a stable id so the
# wire payload survives reorders.
#
# apply_death is idempotent: applying the same death twice (e.g. host's
# broadcast races a local kill detection) returns false the second time
# but doesn't error, mirroring LobbyState.remove_player's contract.
var _alive_enemy_ids: Dictionary = {}  # enemy_id -> true

# Registers a freshly-spawned enemy. Returns true on success, false on
# empty id or duplicate. Idempotent on duplicate so a re-broadcast of
# the spawn event from a flaky network doesn't double-count.
func register_enemy(enemy_id: String) -> bool:
	if enemy_id == "":
		return false
	if _alive_enemy_ids.has(enemy_id):
		return false
	_alive_enemy_ids[enemy_id] = true
	return true

# Removes the enemy from the local registry. Idempotent — applying the
# same death twice returns false the second time but doesn't error.
# Returns true when an enemy was actually removed (so the caller can
# decide whether to award XP / drop loot exactly once).
func apply_death(enemy_id: String) -> bool:
	return _alive_enemy_ids.erase(enemy_id)

func is_alive(enemy_id: String) -> bool:
	return _alive_enemy_ids.has(enemy_id)

func alive_count() -> int:
	return _alive_enemy_ids.size()

func clear() -> void:
	_alive_enemy_ids.clear()
