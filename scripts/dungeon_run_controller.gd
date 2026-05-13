class_name DungeonRunController
extends RefCounted

# Run-state machine over a Dungeon graph. Tracks which room the player is in,
# which rooms have been cleared, and whether the boss has fallen. Pure data —
# no scene tree, no spawning. The (future) spawn / scene layer drives this
# from enemy.died signals and reads `current_room()` to know what to load
# next; the higher orchestrator listens for `dungeon_completed` to call
# DungeonRunCompletion.complete(meta_tracker, inventory).
#
# Why a separate controller (vs. mutating Dungeon directly):
#   - Dungeon is the procedural layout; reusing it across re-runs (e.g. seed
#     replays / shared host-client graph) means run-state has to live
#     elsewhere or the layout gets dirty.
#   - The controller owns the `_cleared` dictionary so a fresh `start(d)`
#     resets state cleanly without rebuilding the graph.
#
# Auto-clear rule: rooms with no seeded enemy (enemy_kind == -1) — start
# rooms and power-up rooms — are considered cleared as soon as they're in
# the dungeon. The player can step through them without an explicit
# mark_room_cleared call. Boss + standard rooms always seed an enemy, so
# they require explicit clearing via mark_room_cleared(room_id) when the
# room's last enemy dies.
#
# Connection rule: advance_to(target) only succeeds when (a) target is in
# current_room().connections and (b) current_room is cleared. Edges are
# directed (Dungeon's BFS / Room.connections semantics) so a room with an
# inbound connection can't be backtracked-into through this API; the
# spawn layer is free to add a separate "go back to previous" affordance
# if design wants one.

signal room_cleared(room_id: int)
signal advanced_to(room_id: int)
signal dungeon_completed()

var dungeon: Dungeon = null
var current_room_id: int = -1
var _cleared: Dictionary = {}
# Source seed for the active dungeon (PRD #42 / #46 save/resume). The
# generator hands back a Dungeon with no provenance, so the orchestrator
# (main_scene._start_new_dungeon, DungeonRunSerializer.deserialize) stamps
# this after generate() so the QuitDungeon save path can serialize it.
# -1 means "no seed recorded yet" — DungeonGenerator's randomize-on-negative
# sentinel, which matches the solo / no-coop default.
var seed: int = -1

func start(d: Dungeon) -> bool:
	if d == null or d.start_id < 0:
		return false
	dungeon = d
	current_room_id = d.start_id
	_cleared = {}
	advanced_to.emit(current_room_id)
	return true

func current_room() -> Room:
	if dungeon == null:
		return null
	return dungeon.get_room(current_room_id)

# True when the room has no enemies left to fight: either it was explicitly
# marked cleared, or it never had an enemy seeded in the first place
# (start / power-up rooms). Boss / standard rooms always have an enemy
# kind set by the generator so they're never auto-cleared.
func is_room_cleared(room_id: int) -> bool:
	if _cleared.get(room_id, false):
		return true
	if dungeon == null:
		return false
	var r := dungeon.get_room(room_id)
	if r == null:
		return false
	return r.enemy_kind == -1

# Returns true on the first mark (a fresh "this room just got cleared"
# transition), false on repeats. Caller drives the per-room enemy-count
# watcher; this function gives the caller a clean edge-trigger so the
# room_cleared signal fires exactly once per room. Emits `room_cleared`
# on the rising edge; emits `dungeon_completed` if the cleared room is
# the boss room.
func mark_room_cleared(room_id: int) -> bool:
	if dungeon == null:
		return false
	var r := dungeon.get_room(room_id)
	if r == null:
		return false
	if _cleared.get(room_id, false):
		return false
	_cleared[room_id] = true
	room_cleared.emit(room_id)
	if room_id == dungeon.boss_id:
		dungeon_completed.emit()
	return true

# Gate for advance_to. Caller can use this to enable / disable a "next room"
# button before the actual transition.
func can_advance_to(target_room_id: int) -> bool:
	if dungeon == null:
		return false
	var current := current_room()
	if current == null:
		return false
	if not is_room_cleared(current_room_id):
		return false
	if not current.connections.has(target_room_id):
		return false
	return dungeon.get_room(target_room_id) != null

func advance_to(target_room_id: int) -> bool:
	if not can_advance_to(target_room_id):
		return false
	current_room_id = target_room_id
	advanced_to.emit(current_room_id)
	return true

# Explicitly-cleared room ids in insertion order. Used by DungeonRunSerializer
# to capture run state for save/resume (PRD #42 / #46). Auto-cleared rooms
# (start, power-up) aren't in `_cleared` and are re-derived from the
# regenerated dungeon on restore, so they're intentionally excluded here.
func cleared_ids() -> Array:
	var ids: Array = []
	for k in _cleared.keys():
		if _cleared[k]:
			ids.append(int(k))
	return ids

func is_dungeon_complete() -> bool:
	if dungeon == null:
		return false
	return _cleared.get(dungeon.boss_id, false)
