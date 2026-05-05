extends GutTest

# Tests for RoomSpawnPlanner — the data-side bridge between Dungeon graph
# Rooms and the spawn-time wiring that KillRewardRouter / EnemyStateSyncManager
# expect (populated EnemyData with stable enemy_id + is_boss).

# --- helpers ---------------------------------------------------------------

func _make_standard_room(room_id: int, kind: int = EnemyData.EnemyKind.SLIME) -> Room:
	var r := Room.make(room_id, Room.TYPE_STANDARD)
	r.enemy_kind = kind
	return r

func _make_boss_room(room_id: int, kind: int = EnemyData.EnemyKind.RAT) -> Room:
	var r := Room.make(room_id, Room.TYPE_BOSS)
	r.enemy_kind = kind
	return r

func _make_powerup_room(room_id: int, type: String = "catnip") -> Room:
	var r := Room.make(room_id, Room.TYPE_POWERUP)
	r.power_up_type = type
	return r

func _make_start_room(room_id: int) -> Room:
	return Room.make(room_id, Room.TYPE_START)

func _make_session_with_lobby() -> CoopSession:
	# Non-empty party so start() can succeed; we only need enemy_sync to
	# exist after start. Single-player lobby + character map.
	var lobby := LobbyState.new()
	lobby.room_code = "ABCDE"
	var p := LobbyPlayer.make("p1", "Whiskers", "Mage", true)
	lobby.add_player(p)
	var c := CharacterFactory.create_default("Mage")
	var characters := {"p1": c}
	var s := CoopSession.new(lobby, characters)
	# Build a tiny dungeon so start() succeeds and enemy_sync is non-null.
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	return s

# --- plan_enemy ------------------------------------------------------------

func test_plan_enemy_standard_room_returns_populated_data():
	var r := _make_standard_room(3, EnemyData.EnemyKind.SLIME)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.SLIME)
	assert_eq(d.enemy_id, "r3_e0", "id format is r{room_id}_e{spawn_idx}")
	assert_false(d.is_boss, "standard room is not a boss room")

func test_plan_enemy_boss_room_sets_is_boss():
	var r := _make_boss_room(7, EnemyData.EnemyKind.RAT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.RAT)
	assert_eq(d.enemy_id, "r7_e0")
	assert_true(d.is_boss, "boss room enemy is flagged for the boss-kill bonus")

func test_plan_enemy_powerup_room_returns_null():
	var r := _make_powerup_room(2)
	assert_null(RoomSpawnPlanner.plan_enemy(r), "power-up rooms have no enemy")

func test_plan_enemy_start_room_returns_null():
	var r := _make_start_room(0)
	assert_null(RoomSpawnPlanner.plan_enemy(r), "start rooms have no enemy")

func test_plan_enemy_null_room_returns_null():
	assert_null(RoomSpawnPlanner.plan_enemy(null), "null room is safe no-op")

func test_plan_enemy_returns_independent_instances():
	# Two calls on the same room should not return the same EnemyData
	# reference (mutating one's hp shouldn't drain the other's).
	var r := _make_standard_room(1)
	var a := RoomSpawnPlanner.plan_enemy(r)
	var b := RoomSpawnPlanner.plan_enemy(r)
	a.take_damage(99)
	assert_eq(a.hp, 0)
	assert_eq(b.hp, b.max_hp, "second instance untouched by first's damage")

func test_plan_enemy_spawn_idx_appears_in_id():
	var r := _make_standard_room(5, EnemyData.EnemyKind.BAT)
	var d := RoomSpawnPlanner.plan_enemy(r, 2)
	assert_eq(d.enemy_id, "r5_e2", "spawn_idx threads through to id")

func test_plan_enemy_max_hp_matches_kind():
	# Pin that we go through EnemyData.make_new (so future stat changes
	# in EnemyData propagate without the planner having to re-pin them).
	var r := _make_standard_room(0, EnemyData.EnemyKind.RAT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_eq(d.max_hp, EnemyData.base_max_hp_for(EnemyData.EnemyKind.RAT))
	assert_eq(d.attack, EnemyData.base_attack_for(EnemyData.EnemyKind.RAT))

# --- enemy_ids_for_room ----------------------------------------------------

func test_enemy_ids_for_standard_room_one_id():
	var r := _make_standard_room(4)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1, "one enemy per combat room today")
	assert_eq(ids[0], "r4_e0")

func test_enemy_ids_for_boss_room_one_id():
	var r := _make_boss_room(9)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1)
	assert_eq(ids[0], "r9_e0")

func test_enemy_ids_for_powerup_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(_make_powerup_room(2)).size(), 0)

func test_enemy_ids_for_start_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(_make_start_room(0)).size(), 0)

func test_enemy_ids_for_null_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(null).size(), 0)

func test_enemy_ids_match_plan_enemy_output():
	# Locks the contract that ids_for_room and plan_enemy agree on the
	# id format — so the per-room watcher's expected-id list and the
	# spawner's actual-EnemyData list don't drift.
	var r := _make_standard_room(11)
	var planned := RoomSpawnPlanner.plan_enemy(r)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1)
	assert_eq(ids[0], planned.enemy_id)

# --- register_room_enemies -------------------------------------------------

func test_register_room_enemies_combat_room_registers_with_session():
	var session := _make_session_with_lobby()
	var room := _make_standard_room(3)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r3_e0")
	assert_true(session.enemy_sync.is_alive("r3_e0"), "registry knows about the spawn")

func test_register_room_enemies_boss_room_sets_is_boss_and_registers():
	var session := _make_session_with_lobby()
	var room := _make_boss_room(7)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(spawned.size(), 1)
	assert_true(spawned[0].is_boss)
	assert_true(session.enemy_sync.is_alive("r7_e0"))

func test_register_room_enemies_powerup_returns_empty_no_registry_change():
	var session := _make_session_with_lobby()
	var before := session.enemy_sync.alive_count()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, _make_powerup_room(2))
	assert_eq(spawned.size(), 0)
	assert_eq(session.enemy_sync.alive_count(), before, "no registry pollution from powerup room")

func test_register_room_enemies_null_session_still_returns_data():
	# Solo / pre-handshake path: session is null. Caller still gets a
	# populated EnemyData (so it can spawn into the scene tree); the
	# kill flow's empty-registry short-circuit keeps solo correct.
	var spawned := RoomSpawnPlanner.register_room_enemies(null, _make_standard_room(1))
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r1_e0")
	assert_false(spawned[0].is_boss)

func test_register_room_enemies_null_room_safe():
	var session := _make_session_with_lobby()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, null)
	assert_eq(spawned.size(), 0, "null room is a safe no-op")

func test_register_room_enemies_session_post_end_safe():
	# Defensive: a race where end() drops enemy_sync before the spawner
	# stops calling. Should still return populated data (so the
	# spawner's instantiation path doesn't crash) without a registry
	# touch.
	var session := _make_session_with_lobby()
	session.end()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, _make_standard_room(1))
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r1_e0")

func test_register_room_enemies_idempotent_on_repeat():
	# Mirrors EnemyStateSyncManager.register_enemy's idempotency: a
	# re-register (e.g. spawn-event re-broadcast) returns the same
	# data without polluting the registry.
	var session := _make_session_with_lobby()
	var room := _make_standard_room(3)
	RoomSpawnPlanner.register_room_enemies(session, room)
	var before := session.enemy_sync.alive_count()
	var second := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(second.size(), 1, "second call still returns the planned spawn")
	assert_eq(session.enemy_sync.alive_count(), before, "no registry growth on repeat")

# --- end-to-end: spawn -> kill -> apply_death --------------------------------

func test_planned_enemy_id_round_trips_through_apply_death():
	# Pins that the id minted by the planner is the same key
	# KillRewardRouter / EnemyStateSyncManager.apply_death use, so a
	# kill flow against a planned spawn idempotently clears the
	# registry.
	var session := _make_session_with_lobby()
	var room := _make_boss_room(4)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_true(session.enemy_sync.is_alive(spawned[0].enemy_id))
	assert_true(session.enemy_sync.apply_death(spawned[0].enemy_id))
	assert_false(session.enemy_sync.is_alive(spawned[0].enemy_id))
