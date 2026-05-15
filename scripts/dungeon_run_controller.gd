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
# As of issue #97 the controller no longer drives room-to-room
# progression: the player walks freely between all rooms on the
# single connected map produced by DungeonLayoutEngine. `current_room_id`
# stays at `start_id` for the run's duration and exists only so the
# serializer can persist save state shape. The advance_to / can_advance_to
# /advanced_to API was removed alongside the HUD's "Next Room" button.

signal room_cleared(room_id: int)
signal dungeon_completed()
# Fires when the boss room is marked cleared — distinct from dungeon_completed
# so the scene layer can react to "boss is down" (open the ExitDoor) without
# entangling with the run-end / meta-bump path that dungeon_completed drives.
# Issue #98: ExitDoor binds to this edge to transition locked -> open.
signal boss_room_cleared()
# Fires when the orchestrator decides to advance from this dungeon into a
# new one. Distinct from dungeon_completed (which is the boss-cleared edge):
# transitioned is the deliberate "load the next dungeon" call, not the
# combat outcome. PRD #52 / #61: main_scene calls transition() on the
# boss-cleared edge, the scene layer listens for this signal to open the
# stat-allocation screen before the reload.
signal dungeon_transitioned()

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
		boss_room_cleared.emit()
		dungeon_completed.emit()
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

# Emits dungeon_transitioned. Called by the scene-layer orchestrator
# (main_scene) when it's about to load the next dungeon — gives listeners
# (the stat-allocation screen, future analytics) a single edge to bind to
# without coupling to the boss-clear path or the scene reload itself.
# Pure data — does not mutate run state; the scene layer is responsible
# for actually reloading after the signal's listeners have run.
func transition() -> void:
	dungeon_transitioned.emit()
