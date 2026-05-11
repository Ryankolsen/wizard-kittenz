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
#      tracker. The lobby is the source of truth for who's in the party;
#      the character map provides each member's real_stats so floor +
#      scaling can be computed at construction time. A lobby player
#      whose player_id has no entry in the map is skipped (defensive
#      against a wire-payload race where a player joined the lobby but
#      their CharacterData hasn't propagated yet).
#   2. Call start(dungeon) to begin a run. Builds the four sync managers
#      + DungeonRunController, registers every party_id with the XP
#      broadcaster, and wires DungeonRunController.dungeon_completed →
#      DungeonRunCompletion.complete on the boss-cleared edge.
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
# Re-emitted from run_controller.dungeon_completed after the meta tracker
# is bumped. The summary screen listens here so it doesn't have to reach
# through to run_controller. Pure pass-through — no payload.
signal run_completed()

var lobby: LobbyState = null
var members: Array[PartyMember] = []
# Parallel to `members`. Looked up by member_for(player_id). Kept as a
# separate array (rather than a Dictionary) so the array iteration order
# matches `lobby.players` order — the summary screen renders rows in
# join order rather than dictionary-iteration order.
var player_ids: Array[String] = []
var floor_level: int = 1
var meta_tracker: MetaProgressionTracker = null
# This client's player_id within the lobby. Drives the LocalXPRouter
# subscription so an xp_awarded(local_player_id, amount) emission lands
# on this client's PartyMember.real_stats. Empty on a default-
# constructed (test / pre-handshake) session — start() simply skips
# building the router in that case (no local id => nothing to filter
# on => no-op subscription).
var local_player_id: String = ""

# Per-run managers — non-null between start() and end(), null otherwise
# so a caller can null-check `xp_broadcaster` to ask "is the run live?".
var xp_broadcaster: XPBroadcaster = null
var xp_summary: RunXPSummary = null
var xp_router: LocalXPRouter = null
var network_sync: NetworkSyncManager = null
var enemy_sync: EnemyStateSyncManager = null
var run_controller: DungeonRunController = null

var _active: bool = false
# Sticky bool flipped true when run_controller.dungeon_completed fires.
# Kept around after end() so a summary screen / "Victory!" header that
# reads the session post-end still sees the completion.
var _dungeon_completed: bool = false

func _init(lobby_state: LobbyState = null, characters: Dictionary = {}, tracker: MetaProgressionTracker = null, local_id: String = "") -> void:
	lobby = lobby_state
	meta_tracker = tracker
	local_player_id = local_id
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

	# Wire the local-routing subscriber only when this session knows
	# which player_id is local AND that player is in the party. A
	# default-constructed session (test / pre-handshake) skips the
	# router; xp_summary still tallies, but no XP lands on any
	# member.real_stats until the session is reconstructed with a
	# local id. Same shape as the network/enemy sync managers — the
	# wire is built but only fires when the inputs are present.
	var local_member := member_for(local_player_id)
	if local_member != null:
		xp_router = LocalXPRouter.new(xp_broadcaster, local_player_id, local_member)

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

func was_dungeon_completed() -> bool:
	return _dungeon_completed

func _on_dungeon_completed() -> void:
	DungeonRunCompletion.complete(meta_tracker)
	_dungeon_completed = true
	run_completed.emit()

func _drop_managers() -> void:
	if xp_summary != null and xp_broadcaster != null:
		xp_summary.unbind(xp_broadcaster)
	if xp_router != null:
		xp_router.unbind()
	xp_broadcaster = null
	xp_summary = null
	xp_router = null
	network_sync = null
	enemy_sync = null
	run_controller = null
