class_name RoomClearWatcher
extends RefCounted

# Per-room enemy-count watcher. Tracks the set of enemy_ids spawned in
# a single room and fires DungeonRunController.mark_room_cleared(room.id)
# on the last expected death. Bridges two existing seams:
#   - RoomSpawnPlanner.enemy_ids_for_room(room) — what to expect
#   - DungeonRunController.mark_room_cleared(id)  — what to fire
# so the future scene-tree spawner doesn't have to count deaths inline
# at every per-room call site.
#
# Closes the recurring "per-room enemy-count watcher (the piece that
# calls run_controller.mark_room_cleared on the last enemy's died
# signal) is the next adjacent seam" gap mentioned in c0f9a23's
# RoomSpawnPlanner landing.
#
# Lifecycle: one watcher per room. The future spawn layer constructs a
# watcher on room enter via watch(room, controller), calls
# notify_death(enemy_id) on every enemy.died signal (whether from local
# kill detection or remote apply_death), and drops the watcher on room
# exit. RefCounted lifetime drops it as soon as the parent falls out
# of scope.
#
# Auto-clear rule: rooms with no expected enemies (power-up / start)
# fire mark_room_cleared immediately on watch() so the player can
# advance without a kill. Combat rooms wait for the last expected
# death. Mirrors DungeonRunController.is_room_cleared's auto-clear
# rule for enemy_kind == -1 rooms — keeping the auto-clear edge in
# both places means a watcher's mark_room_cleared call returns false
# (already cleared by the controller's own auto-clear) without
# error, but the watcher's _cleared flag still flips so a stray
# notify_death is a safe no-op.
#
# Idempotency / defensiveness:
#   - notify_death(unknown_id) is a safe no-op (returns false). A
#     remote enemy-died packet for an enemy in a different room
#     will not falsely clear this room — the per-room expected set
#     is the gate.
#   - notify_death after cleared is a safe no-op. The watcher fires
#     mark_room_cleared at most once across its lifetime.
#   - notify_death("") is a safe no-op (defensive against the empty-
#     id sentinel from EnemyData's pre-spawn-layer fixtures).
#   - re-watch() on the same instance resets state cleanly (clears
#     prior expected set and _cleared flag).

# Per-room XP reward (PRD #52). Awarded on the last expected death
# of a combat room. No-enemy rooms (start, power-up) auto-clear on
# watch() and intentionally do NOT pay out — the reward fires from
# combat, not traversal.
const ROOM_CLEAR_XP: int = 50

# Per-room Gold bonus (PRD #53). Credited to the local CurrencyLedger on the
# last expected death of a combat room. Auto-clear rooms (start, power-up)
# do NOT pay out — same combat-only rule as ROOM_CLEAR_XP.
const ROOM_CLEAR_GOLD: int = 10

var room_id: int = -1
var controller: DungeonRunController = null
var _expected: Dictionary = {}  # enemy_id -> true
var _initial_count: int = 0
var _cleared: bool = false
var _character: CharacterData = null
var _session: CoopSession = null
var _ledger: CurrencyLedger = null
var _tree: SkillTree = null

# Begins watching a room. Returns true on success, false on null
# inputs. Reads expected enemy_ids from RoomSpawnPlanner so the
# watcher and the spawner stay locked to the same id format.
# Auto-fires mark_room_cleared for rooms with no expected enemies
# (power-up / start) so DungeonRunController.is_room_cleared returns
# true and the player can advance without a kill.
#
# Optional `character` / `session` references opt the watcher into
# the PRD #52 room-clear XP award. Solo callers pass `character`;
# co-op callers pass `session` (the watcher routes through the
# party-split broadcaster). Tests / pre-spawn-layer paths can omit
# both — the watcher still tracks the cleared edge but pays no XP.
func watch(room: Room, c: DungeonRunController, character: CharacterData = null, session: CoopSession = null, ledger: CurrencyLedger = null, tree: SkillTree = null) -> bool:
	if room == null or c == null:
		return false
	room_id = room.id
	controller = c
	_character = character
	_session = session
	_ledger = ledger
	_tree = tree
	_expected.clear()
	_cleared = false
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	_initial_count = ids.size()
	for enemy_id in ids:
		_expected[enemy_id] = true
	if _expected.is_empty():
		_cleared = true
		controller.mark_room_cleared(room_id)
	return true

# Records a death. Returns true exactly once — on the death that
# clears the last expected enemy (the rising-edge of "room cleared").
# Returns false on:
#   - empty enemy_id (defensive against pre-spawn-layer fixtures)
#   - unknown enemy_id (not from this room — defensive against
#     remote enemy-died packets for other rooms)
#   - already cleared (idempotent — a second notify after the room
#     fired is a safe no-op)
#   - intermediate death in a multi-spawn room (still expecting
#     more deaths before the room clears)
func notify_death(enemy_id: String) -> bool:
	if _cleared:
		return false
	if enemy_id == "":
		return false
	if not _expected.has(enemy_id):
		return false
	_expected.erase(enemy_id)
	if _expected.is_empty():
		_cleared = true
		_award_room_clear_xp()
		_award_room_clear_gold()
		if controller != null:
			controller.mark_room_cleared(room_id)
		return true
	return false

# PRD #52 room-clear XP payout. Routes through the same solo/co-op
# fork as KillRewardRouter: an active co-op session fans XP through
# the party-split broadcaster (each member receives the same per-
# player share); solo path adds XP directly to the watched character.
# Either reference may be null (test path / pre-spawn-layer); a null
# session falls back to solo, a null character degrades to a no-op.
func _award_room_clear_xp() -> void:
	if _session != null and _session.is_active() and _session.xp_broadcaster != null:
		var per_player := KillRewardRouter.xp_per_player(
			ROOM_CLEAR_XP, _session.xp_broadcaster.player_count())
		_session.xp_broadcaster.on_enemy_killed(per_player, "")
		return
	if _character != null:
		# Issue #126 follow-up: threading `_tree` so a room-clear
		# level-up immediately auto-unlocks newly-eligible SkillNodes
		# rather than deferring until the next set_character pass.
		ProgressionSystem.add_xp(_character, ROOM_CLEAR_XP, _ledger, _tree)

# PRD #53 room-clear Gold bonus. Credited directly to the local
# CurrencyLedger on the last expected death of a combat room. Same
# full-amount rule for solo and co-op (Gold is per-character, not
# split). Null ledger is a silent no-op (test path / pre-wiring).
func _award_room_clear_gold() -> void:
	if _ledger == null:
		return
	_ledger.credit(ROOM_CLEAR_GOLD, CurrencyLedger.Currency.GOLD)

func is_cleared() -> bool:
	return _cleared

func remaining_count() -> int:
	return _expected.size()

func initial_count() -> int:
	return _initial_count
