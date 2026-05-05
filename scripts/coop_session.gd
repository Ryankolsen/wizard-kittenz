class_name CoopSession
extends RefCounted

# Per-match orchestrator. Owns the lifetime of the per-run managers
# (XPBroadcaster, RunXPSummary, NetworkSyncManager, EnemyStateSyncManager,
# DungeonRunController) and the per-member scaling state. The recurring
# "no place to construct managers per match" gap mentioned across #16,
# #17, #18, #20 closes here.
#
# Lifecycle:
#   1. Construct with a LobbyState + per-player_id character map + meta
#      tracker + token inventory. The lobby is the source of truth for
#      who's in the party; the character map provides each member's
#      real_stats so floor + scaling can be computed at construction
#      time. A lobby player whose player_id has no entry in the map is
#      skipped (defensive against a wire-payload race where a player
#      joined the lobby but their CharacterData hasn't propagated yet).
#   2. Call start(dungeon) to begin a run. Builds the four sync managers
#      + DungeonRunController, registers every party_id with the XP
#      broadcaster, and wires DungeonRunController.dungeon_completed →
#      DungeonRunCompletion.complete on the boss-cleared edge. The
#      grant count is re-emitted via dungeon_completed_grant so the
#      future "+N tokens" toast UI just listens to the session, not
#      the run-completion helper.
#   3. Call end() on session teardown (player back-out, dungeon failed,
#      next-run reset). Removes scaling from every member (real ==
#      effective again), unbinds the summary from the broadcaster, drops
#      every per-run manager reference. Idempotent — calling end() when
#      not active returns false but doesn't error.
#
# Pure data — no scene tree, no autoloads. The future co-op orchestrator
# scene instantiates this once per match and drops the reference on
# session end. RefCounted lifetime drops the children (managers, members)
# as soon as the parent falls out of scope.
#
# What this does NOT do:
#   - Apply XP to member real_stats. The XPBroadcaster fan-out gives
#     (player_id, amount); each client decides how to route its own
#     player_id's amount through XPSystem.award. Auto-routing here would
#     wrongly mutate remote players' stats from the local client.
#   - Construct the LobbyState or characters map. Those come from the
#     lobby UI / Nakama handshake; this orchestrator just consumes them.
#   - Run any signals through Nakama. The wire layer (#14, HITL) bridges
#     packet I/O to apply_remote_state / apply_death; this session just
#     hands out the manager references for the bridge to call.

signal session_started()
signal session_ended()
signal dungeon_completed_grant(tokens_granted: int)

var lobby: LobbyState = null
var members: Array[PartyMember] = []
# Parallel to `members`. Looked up by member_for(player_id). Kept as a
# separate array (rather than a Dictionary) so the array iteration order
# matches `lobby.players` order — the summary screen renders rows in
# join order rather than dictionary-iteration order.
var player_ids: Array[String] = []
var floor_level: int = 1
var meta_tracker: MetaProgressionTracker = null
var inventory: TokenInventory = null

# Per-run managers — non-null between start() and end(), null otherwise
# so a caller can null-check `xp_broadcaster` to ask "is the run live?".
var xp_broadcaster: XPBroadcaster = null
var xp_summary: RunXPSummary = null
var network_sync: NetworkSyncManager = null
var enemy_sync: EnemyStateSyncManager = null
var run_controller: DungeonRunController = null

var _active: bool = false
# Tokens granted on the most recent dungeon completion. Kept around after
# end() so a "+N tokens" toast on the summary screen can read it without
# re-running the completion logic.
var _last_completion_grant: int = 0

func _init(lobby_state: LobbyState = null, characters: Dictionary = {}, tracker: MetaProgressionTracker = null, inv: TokenInventory = null) -> void:
	lobby = lobby_state
	meta_tracker = tracker
	inventory = inv
	if lobby == null:
		return
	var levels: Array = []
	for p in lobby.players:
		if p == null or p.player_id == "":
			continue
		var c: CharacterData = characters.get(p.player_id)
		if c == null:
			continue
		levels.append(c.level)
		members.append(PartyMember.from_character(c))
		player_ids.append(p.player_id)
	floor_level = PartyScaler.compute_floor(levels)
	for m in members:
		m.apply_scaling(floor_level)

# Begins the run. Builds the four sync managers + DungeonRunController,
# registers every party_id with the XP broadcaster, and wires the boss-
# cleared edge to DungeonRunCompletion. Returns true on success, false on:
#   - already active (idempotent — a second start() is a no-op)
#   - null dungeon (or one with start_id < 0; same gate as
#     DungeonRunController.start)
#   - empty party (nothing to scale, nothing to register — likely a
#     mis-constructed session)
# Rolls back manager construction on a failed run_controller.start so a
# rejected dungeon doesn't leave half-built sync managers around.
func start(dungeon: Dungeon) -> bool:
	if _active:
		return false
	if dungeon == null:
		return false
	if members.is_empty():
		return false

	xp_broadcaster = XPBroadcaster.new()
	xp_summary = RunXPSummary.new(xp_broadcaster)
	network_sync = NetworkSyncManager.new()
	enemy_sync = EnemyStateSyncManager.new()
	run_controller = DungeonRunController.new()

	for pid in player_ids:
		xp_broadcaster.register_player(pid)

	if not run_controller.start(dungeon):
		_drop_managers()
		return false

	run_controller.dungeon_completed.connect(_on_dungeon_completed)
	_active = true
	session_started.emit()
	return true

# Tears down the run. Removes scaling from every member (real_stats ==
# effective_stats), unbinds the summary, drops every per-run manager.
# Idempotent — second call returns false. Members + lobby + floor_level
# survive end() so the same session object can be re-started against a
# new dungeon (the next run in a multi-run match) without losing the
# party roster.
func end() -> bool:
	if not _active:
		return false
	for m in members:
		PartyScaler.remove_scaling(m)
	_drop_managers()
	_active = false
	session_ended.emit()
	return true

func is_active() -> bool:
	return _active

func member_for(player_id: String) -> PartyMember:
	var idx := player_ids.find(player_id)
	if idx < 0:
		return null
	return members[idx]

func member_count() -> int:
	return members.size()

func last_completion_grant() -> int:
	return _last_completion_grant

func _on_dungeon_completed() -> void:
	_last_completion_grant = DungeonRunCompletion.complete(meta_tracker, inventory)
	dungeon_completed_grant.emit(_last_completion_grant)

func _drop_managers() -> void:
	if xp_summary != null and xp_broadcaster != null:
		xp_summary.unbind(xp_broadcaster)
	xp_broadcaster = null
	xp_summary = null
	network_sync = null
	enemy_sync = null
	run_controller = null
