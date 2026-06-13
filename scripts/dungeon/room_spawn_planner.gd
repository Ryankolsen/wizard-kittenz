class_name RoomSpawnPlanner
extends RefCounted

# Instance-mode state: populated by register_all_room_enemies. Maps room_id ->
# EnemyData so the scene-tree spawner can look up the planned spawn for each
# combat room without re-deriving the id / position / boss flag at every call
# site. Empty until register_all_room_enemies fires; the legacy static API
# (plan_enemy / enemy_ids_for_room / register_room_enemies) ignores this dict
# and keeps working unchanged so existing call sites (RoomClearWatcher,
# main_scene's per-room setup) aren't disturbed.
var _enemy_data_by_room_id: Dictionary = {}

# Pure-data bridge between Dungeon graph (Room.enemy_kind / Room.type) and the
# spawn-time wiring KillRewardRouter / EnemyStateSyncManager expect (populated
# EnemyData with stable enemy_id + is_boss flag). The future scene-tree
# spawner consumes this planner's output to know what to instantiate per
# room without re-deriving id format / boss flag at every call site.
#
# Closes the recurring "no call site mints enemy_ids yet — the dungeon
# spawn layer (when it lands) is the owner" gap mentioned in 5804cc2's
# KillRewardRouter.apply_death wire-up. Until the actual scene-tree
# spawner lands, the planner is the data half of the bridge: a Room goes
# in, a populated EnemyData (with id minted, is_boss set, kind copied)
# comes out, and register_room_enemies hands the same record to the
# session's enemy_sync.
#
# Why not put this on Room.gd directly:
#   - Room is the procedural-graph data record (id / type / connections /
#     enemy_kind / power_up_type). Mixing in spawn-time concerns (boss
#     flag derived from type, stable id format, registry side effects)
#     would couple the graph layer to the run layer. The planner
#     consumes Room and is consumed by the spawner — same separation
#     as DungeonRunController / Dungeon.
#
# Why not put this on DungeonGenerator:
#   - The generator's job is graph layout. It runs once per match (or
#     once per replay seed). The planner runs per-room at spawn time,
#     which is a different lifetime. Keeping them separate also lets a
#     future "regenerate this room's enemies on retry" path touch only
#     the planner.
#
# Enemy-id format: "r{room_id}_e{spawn_idx}". Lexically sortable,
# collision-free for any (room, idx) pair, mirrors the format hinted in
# 5804cc2's commit notes ("r3_e0" for room 3 enemy 0). The wire layer's
# enemy-died packet uses this same key so host + remote converge through
# EnemyStateSyncManager.apply_death(enemy_id).
#
# Current shape: one enemy per combat room. Mirrors the generator's
# current "Each combat room (standard + boss) seeds an enemy kind"
# rule. When a future "two enemies per standard room" requirement
# lands, plan_room grows a per-spawn-index loop and the existing call
# sites (register_room_enemies, enemy_ids_for_room) get the multi-id
# fan-out for free.

# Returns a populated EnemyData for a combat room, or null otherwise.
# Combat rooms are TYPE_STANDARD and TYPE_BOSS (the only types the
# generator seeds with an enemy_kind). Start / power-up rooms return
# null — the spawner reads the return value's null-ness to decide
# whether to instantiate an enemy node at all. spawn_idx defaults to 0
# (one enemy per room today); the multi-spawn-per-room future call
# site passes 1, 2, ... for additional spawns.
# Boss multipliers and per-floor scaling rates live on BossScaling (extracted
# in #323 so #324 party-size and #325 average-level scaling can stack on top
# of the boss baseline without piling more scaling logic into the planner).
# Boss room is 24x24 tiles at 16 px each = 384x384 px. A player entering at
# any wall edge is at most ~272 px (half-diagonal) from the room center.
# 300 px gives the boss sight-line to the doorway without reaching into the corridor.
const BOSS_DETECTION_RADIUS: float = 300.0

static func plan_enemy(room: Room, spawn_idx: int = 0, floor_number: int = 1, party_size: int = 1, avg_party_level: float = -1.0, floor_baseline_level: int = -1, kind_override: int = -1) -> EnemyData:
	if room == null:
		return null
	# kind_override lets the multi-mob fan-out (#372) pick a specific kind from
	# room.enemy_kinds while keeping single-mob callers untouched. Default -1
	# falls back to the room's legacy single enemy_kind field.
	var kind: int = kind_override if kind_override >= 0 else room.enemy_kind
	if kind < 0:
		return null
	var data := EnemyData.make_new(kind)
	data.enemy_id = "r%d_e%d" % [room.id, spawn_idx]
	data.is_boss = (room.type == Room.TYPE_BOSS)
	# Stamp mob level for standard mobs (PRD #376 / issue #377). Boss level
	# is a later slice — bosses keep the default level value here so the
	# display surface in #382 can fold a boss-specific level in then.
	# Elite flag + level bonus (PRD #380) come from the parallel arrays
	# RoomPopulationPlanner stamped on the room at generation time, indexed
	# by spawn_idx. Pre-#380 fixtures / rooms with empty arrays default to
	# non-elite with 0 bonus so legacy callers and serialized rooms keep
	# their stats.
	if not data.is_boss:
		var elite_flag: bool = false
		var elite_bonus: int = 0
		if spawn_idx < room.enemy_elites.size():
			elite_flag = room.enemy_elites[spawn_idx]
		if spawn_idx < room.enemy_elite_bonuses.size():
			elite_bonus = room.enemy_elite_bonuses[spawn_idx]
		data.is_elite = elite_flag
		data.level = EnemyLevel.compute_level(kind, floor_number) + elite_bonus
	if data.is_boss:
		# Stamp boss level off the floor baseline (PRD #376 / issue #382) so
		# the boss HUD bar surfaces "Lv N" with the same scale as mob levels.
		# Mirrors the floor-derived baseline BossScaling already uses for
		# level-mult clamps — single source of truth for "what level is this
		# floor's content" across both presentation and stat scaling.
		data.level = BossScaling.baseline_level_for_floor(floor_number)
		var scaled := BossScaling.compute_boss_stats({
			"hp": data.max_hp,
			"attack": data.attack,
			"defense": data.defense,
			"xp": data.xp_reward,
			"gold": data.gold_reward,
		}, floor_number, party_size, avg_party_level, floor_baseline_level)
		data.max_hp = scaled["hp"]
		data.hp = data.max_hp
		data.attack = scaled["attack"]
		data.defense = scaled["defense"]
		data.xp_reward = scaled["xp"]
		data.gold_reward = scaled["gold"]
		# Display name comes from BossRoster (stamped on the Room by the
		# generator) so each floor's boss surfaces its flavor name —
		# "Vacuum" for ROGUE_ROOMBA, "Sir Pickleton" for SIR_PICKLETON, etc.
		# (#302 reads this on the HUD.) Legacy rooms whose generator predates
		# BossRoster left boss_display_name empty; fall back to "The Vacuum"
		# there so existing saves keep their boss-name surface.
		if room.boss_display_name == "":
			data.enemy_name = "The Vacuum"
		else:
			data.enemy_name = room.boss_display_name
		data.detection_radius = BOSS_DETECTION_RADIUS
		data.boss_sprite_left_path = room.boss_sprite_left_path
		data.boss_sprite_right_path = room.boss_sprite_right_path
	else:
		# Standard mobs route through StandardEnemyScaling (#379), which owns
		# the level-growth curve + party guardrails for the non-boss path.
		# Floor-1 / solo / on-baseline is identity, so the per-kind base
		# profiles from #378 show through unchanged on floor 1.
		var scaled := StandardEnemyScaling.compute_standard_stats({
			"hp": data.max_hp,
			"attack": data.attack,
			"defense": data.defense,
			"xp": data.xp_reward,
			"gold": data.gold_reward,
		}, data.level, floor_number, party_size, avg_party_level, floor_baseline_level, data.is_elite)
		data.max_hp = scaled["hp"]
		data.hp = data.max_hp
		data.attack = scaled["attack"]
		data.defense = scaled["defense"]
		data.xp_reward = scaled["xp"]
		data.gold_reward = scaled["gold"]
	return data

# Returns the power-up type string for a power-up room, or empty string
# otherwise. Sibling to plan_enemy: the future scene-tree spawn layer
# reads this to know whether to instantiate a PowerUpPickup and which
# effect to attach. The String contract (rather than a populated record
# like plan_enemy's EnemyData) is intentional — power-ups don't go
# through any registry / network sync the way enemies do, so all the
# spawner needs is the type id to feed PowerUpEffect.make at pickup
# time.
#
# Returns "" (empty string, not null) for non-power-up rooms and null
# inputs. Empty string is the "no power-up here" sentinel — same shape
# as Room.power_up_type's default. The spawner does an `is_empty()` /
# `== ""` check rather than null-check so the call site stays
# match-friendly.
#
# Does NOT validate that room.power_up_type is in PowerUpEffect's known
# set ({catnip, ale, mushrooms}). The generator is the source of truth
# for what gets seeded; PowerUpEffect.make at pickup time is the late
# gate (returns null on unknown id so a stale-save typo no-ops without
# crashing). Mirroring the same gate here would couple the planner to
# the effect catalog without buying any extra safety.
static func plan_powerup(room: Room) -> String:
	if room == null:
		return ""
	if room.type != Room.TYPE_POWERUP:
		return ""
	return room.power_up_type

# Returns the list of enemy_ids that plan_enemy would mint for this
# room. Useful for the per-room enemy-count watcher to know up-front how
# many deaths it needs to see before calling mark_room_cleared. Empty
# array for non-combat rooms (the watcher then auto-clears via
# DungeonRunController.is_room_cleared).
static func enemy_ids_for_room(room: Room) -> Array[String]:
	var ids: Array[String] = []
	if room == null:
		return ids
	# Prefer the multi-mob enemy_kinds list (#371). Fall back to the legacy
	# single enemy_kind field so pre-#371 test fixtures and serialized rooms
	# still mint one id (the per-room watcher's expected set matches the
	# spawn planner's actual list).
	var n: int = room.enemy_kinds.size()
	if n == 0 and room.enemy_kind >= 0:
		n = 1
	for idx in range(n):
		ids.append("r%d_e%d" % [room.id, idx])
	return ids

# Builds + registers every enemy this room will spawn. Returns the list
# of EnemyData records the spawner should instantiate into the scene
# tree (so register-then-spawn happens through a single seam — no
# chance of registering an id the spawner forgot to spawn or vice
# versa). When session is null (solo / pre-handshake / test path),
# returns the populated EnemyData(s) without touching any registry —
# the kill-flow's empty-registry short-circuit (KillRewardRouter)
# keeps solo behavior unchanged. When session is non-null but
# session.enemy_sync is null (post-end() race), the registration is
# silently skipped; the EnemyData(s) still carry their minted ids so
# a subsequent kill flow doesn't crash on a half-built session.
static func register_room_enemies(session: CoopSession, room: Room, floor_number: int = 1) -> Array[EnemyData]:
	var spawned: Array[EnemyData] = []
	if room == null:
		return spawned
	var kinds: Array = _kinds_for_room(room)
	if kinds.is_empty():
		return spawned
	var party_size: int = _party_size_from_session(session)
	var avg_level: float = _avg_party_level_from_session(session)
	var baseline_level: int = BossScaling.baseline_level_for_floor(floor_number)
	for spawn_idx in range(kinds.size()):
		var kind: int = kinds[spawn_idx]
		var data := plan_enemy(room, spawn_idx, floor_number, party_size, avg_level, baseline_level, kind)
		if data == null:
			continue
		if session != null and session.enemy_sync != null:
			session.enemy_sync.register_enemy(data.enemy_id)
		spawned.append(data)
	return spawned

# Returns the list of enemy kinds this room should spawn. Prefer the multi-mob
# enemy_kinds list (#371); fall back to the legacy single enemy_kind so test
# fixtures and pre-#371 serialized rooms still spawn one mob.
static func _kinds_for_room(room: Room) -> Array:
	if room == null:
		return []
	if room.enemy_kinds.size() > 0:
		return room.enemy_kinds
	if room.enemy_kind >= 0:
		return [room.enemy_kind]
	return []

# Plans and (in co-op) registers every combat room's enemy in a single pass at
# dungeon load. Replaces the lazy "spawn on room enter" pattern with an
# upfront fan-out so all enemies exist simultaneously in the scene tree (issue
# #96). The DungeonLayout is required to mint spawn_position values from each
# room's world center — the scene-tree spawner reads those positions to drop
# the enemy node at the right pixel coordinate.
#
# Returns the flat list of enemy_ids minted across all combat rooms. Caller
# (main_scene) iterates the planner's per-room map via enemy_data_for_room to
# instantiate Enemy nodes. Solo / null-session path is a registry-touch-free
# data populate; co-op path also calls session.enemy_sync.register_enemy for
# each id so OP_KILL packets converge at the receiving client.
#
# Idempotent on the registry side — session.enemy_sync.register_enemy itself
# is a no-op on a repeat id, so calling this twice in a row (e.g. across a
# scene reload during the deprecation of advance_to) doesn't pollute the
# registry. The internal map is rebuilt from scratch each call so a fresh
# dungeon doesn't inherit a stale prior run's entries.
func register_all_room_enemies(dungeon: Dungeon, layout: DungeonLayout, session: CoopSession = null, floor_number: int = 1) -> Array[String]:
	var ids: Array[String] = []
	_enemy_data_by_room_id.clear()
	if dungeon == null:
		return ids
	var party_size: int = _party_size_from_session(session)
	var avg_level: float = _avg_party_level_from_session(session)
	var baseline_level: int = BossScaling.baseline_level_for_floor(floor_number)
	for room in dungeon.rooms:
		var kinds: Array = _kinds_for_room(room)
		if kinds.is_empty():
			continue
		# Compute spread positions once per room. Boss rooms only have one
		# slot, so the spreader returns the room center — same as the
		# pre-#372 single-mob center placement.
		var positions: Array = []
		if layout != null:
			var rect: Rect2 = layout.room_rect_world(room.id)
			if rect.size != Vector2.ZERO:
				positions = SpawnPositionSpreader.spread(rect.position, rect.size, kinds.size())
		var room_records: Array[EnemyData] = []
		for spawn_idx in range(kinds.size()):
			var kind: int = kinds[spawn_idx]
			var data := plan_enemy(room, spawn_idx, floor_number, party_size, avg_level, baseline_level, kind)
			if data == null:
				continue
			if spawn_idx < positions.size():
				data.spawn_position = positions[spawn_idx]
			if data.is_boss and layout != null:
				data.room_bounds = layout.boss_room_bounds(room.id)
			room_records.append(data)
			if session != null and session.enemy_sync != null:
				session.enemy_sync.register_enemy(data.enemy_id)
			ids.append(data.enemy_id)
		if not room_records.is_empty():
			_enemy_data_by_room_id[room.id] = room_records
	return ids

# Per-room lookup of the first EnemyData minted by register_all_room_enemies.
# Returns null for non-combat rooms and for rooms not yet planned. Kept for
# backward-compat with the single-mob consumers (main_scene's spawn loop, tests
# pinning the boss record); the multi-mob spawner (#374) reads
# enemy_data_list_for_room instead.
func enemy_data_for_room(room_id: int) -> EnemyData:
	if not _enemy_data_by_room_id.has(room_id):
		return null
	var arr: Array = _enemy_data_by_room_id[room_id]
	if arr.is_empty():
		return null
	return arr[0]

# Full list of EnemyData records planned for this room (#372). One entry per
# spawned mob; empty array for non-combat rooms and for rooms not yet planned.
# The scene-tree spawner iterates this list to instantiate one Enemy node per
# mob with its own spread spawn_position.
func enemy_data_list_for_room(room_id: int) -> Array[EnemyData]:
	if not _enemy_data_by_room_id.has(room_id):
		var empty: Array[EnemyData] = []
		return empty
	return _enemy_data_by_room_id[room_id]

# Returns the list of combat room ids the planner has spawned for. Useful for
# the scene-tree spawner to know which rooms to iterate without re-deriving
# the combat-room filter from the dungeon graph.
func planned_room_ids() -> Array:
	return _enemy_data_by_room_id.keys()

# Reads party size from the session's member list (PRD #322 / issue #324).
# Null session is solo (1). Empty member list also falls back to 1 so a
# pre-handshake call to the planner doesn't accidentally apply solo-scale
# from an honest 0 — BossScaling treats 0 as solo too, but the explicit
# floor here keeps the contract symmetric and the intent visible.
static func _party_size_from_session(session: CoopSession) -> int:
	if session == null:
		return 1
	var n: int = session.member_count()
	if n <= 0:
		return 1
	return n

# Reads average party level from the session's member list (PRD #322 / issue
# #325). Null session and empty member list both fall back to level 1 — solo
# / pre-handshake callers shouldn't accidentally invoke a 0.7× under-baseline
# scaling from an "honest 0" average. Real character level (real_stats.level)
# is the input; effective_stats are the in-game scaled view (PartyScaler)
# and would confuse the boss-difficulty intent.
static func _avg_party_level_from_session(session: CoopSession) -> float:
	if session == null:
		return 1.0
	if session.members.is_empty():
		return 1.0
	var total: float = 0.0
	for m in session.members:
		total += float(m.real_stats.level)
	return total / float(session.members.size())
