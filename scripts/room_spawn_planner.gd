class_name RoomSpawnPlanner
extends RefCounted

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
static func plan_enemy(room: Room, spawn_idx: int = 0) -> EnemyData:
	if room == null:
		return null
	if room.enemy_kind < 0:
		return null
	var data := EnemyData.make_new(room.enemy_kind)
	data.enemy_id = "r%d_e%d" % [room.id, spawn_idx]
	data.is_boss = (room.type == Room.TYPE_BOSS)
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
	if room == null or room.enemy_kind < 0:
		return ids
	# One enemy per combat room today. When a future "multiple enemies
	# per standard room" rule lands, the loop bound becomes
	# enemies_per_room(room) and plan_enemy gets the matching spawn_idx.
	ids.append("r%d_e%d" % [room.id, 0])
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
static func register_room_enemies(session: CoopSession, room: Room) -> Array[EnemyData]:
	var spawned: Array[EnemyData] = []
	if room == null or room.enemy_kind < 0:
		return spawned
	# Mirrors enemy_ids_for_room's loop bound — one enemy per combat
	# room today; the multi-spawn future grows here.
	for spawn_idx in range(1):
		var data := plan_enemy(room, spawn_idx)
		if data == null:
			continue
		if session != null and session.enemy_sync != null:
			session.enemy_sync.register_enemy(data.enemy_id)
		spawned.append(data)
	return spawned
