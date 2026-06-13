extends GutTest

# Tests for RoomSpawnPlanner — the data-side bridge between Dungeon graph
# Rooms and the spawn-time wiring that KillRewardRouter / EnemyStateSyncManager
# expect (populated EnemyData with stable enemy_id + is_boss).

# --- helpers ---------------------------------------------------------------

func _make_standard_room(room_id: int, kind: int = EnemyData.EnemyKind.ANGRY_PIGEON) -> Room:
	var r := Room.make(room_id, Room.TYPE_STANDARD)
	r.enemy_kind = kind
	return r

func _make_boss_room(room_id: int, kind: int = EnemyData.EnemyKind.DOG_KNIGHT) -> Room:
	var r := Room.make(room_id, Room.TYPE_BOSS)
	r.enemy_kind = kind
	return r

func _make_powerup_room(room_id: int, type: String = "catnip") -> Room:
	var r := Room.make(room_id, Room.TYPE_POWERUP)
	r.power_up_type = type
	return r

func _make_start_room(room_id: int) -> Room:
	return Room.make(room_id, Room.TYPE_START)

func _make_session_with_n_members(n: int) -> CoopSession:
	# Multi-member variant of _make_session_with_lobby. Used by the party-
	# size scaling tests (#324) to exercise the planner's party_size derive.
	var lobby := LobbyState.new()
	lobby.room_code = "ABCDE"
	var characters: Dictionary = {}
	for i in range(n):
		var pid := "p%d" % (i + 1)
		var p := LobbyPlayer.make(pid, "K%d" % (i + 1), "Mage", i == 0)
		lobby.add_player(p)
		characters[pid] = CharacterFactory.create_default("Mage")
	var s := CoopSession.new(lobby, characters)
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	return s

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
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	return s

# --- plan_enemy ------------------------------------------------------------

func test_plan_enemy_standard_room_returns_populated_data():
	var r := _make_standard_room(3, EnemyData.EnemyKind.ANGRY_PIGEON)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(d.enemy_id, "r3_e0", "id format is r{room_id}_e{spawn_idx}")
	assert_false(d.is_boss, "standard room is not a boss room")

func test_plan_enemy_boss_room_sets_is_boss():
	var r := _make_boss_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.DOG_KNIGHT)
	assert_eq(d.enemy_id, "r7_e0")
	assert_true(d.is_boss, "boss room enemy is flagged for the boss-kill bonus")

func test_plan_enemy_boss_room_has_boosted_stats():
	var r := _make_boss_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	var base_hp := EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT)
	var base_atk := EnemyData.base_attack_for(EnemyData.EnemyKind.DOG_KNIGHT)
	var base_def := EnemyData.base_defense_for(EnemyData.EnemyKind.DOG_KNIGHT)
	assert_eq(d.max_hp, int(roundf(float(base_hp) * BossScaling.BOSS_HP_MULT)))
	assert_eq(d.hp, d.max_hp, "hp starts full")
	assert_eq(d.attack, int(roundf(float(base_atk) * BossScaling.BOSS_ATTACK_MULT)))
	assert_eq(d.defense, int(roundf(float(base_def) * BossScaling.BOSS_DEFENSE_MULT)))
	assert_eq(d.xp_reward, int(roundf(float(EnemyData.base_xp_for(EnemyData.EnemyKind.DOG_KNIGHT)) * BossScaling.BOSS_XP_MULT)))
	assert_eq(d.gold_reward, int(roundf(float(EnemyData.base_gold_for(EnemyData.EnemyKind.DOG_KNIGHT)) * BossScaling.BOSS_GOLD_MULT)))
	assert_eq(d.enemy_name, "The Vacuum")

func test_plan_enemy_boss_room_has_wide_detection_radius():
	var r := _make_boss_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_eq(d.detection_radius, RoomSpawnPlanner.BOSS_DETECTION_RADIUS,
		"boss detects player anywhere in the 384x384 boss room")
	var standard := _make_standard_room(3, EnemyData.EnemyKind.DOG_KNIGHT)
	var sd := RoomSpawnPlanner.plan_enemy(standard)
	assert_lt(sd.detection_radius, RoomSpawnPlanner.BOSS_DETECTION_RADIUS,
		"standard enemy has a shorter detection radius than the boss")

func test_plan_enemy_standard_room_not_boosted():
	var r := _make_standard_room(3, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_eq(d.max_hp, EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT), "standard RAT is unmodified")
	assert_eq(d.attack, EnemyData.base_attack_for(EnemyData.EnemyKind.DOG_KNIGHT))
	assert_false(d.is_boss)

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
	var r := _make_standard_room(5, EnemyData.EnemyKind.ROGUE_ROOMBA)
	var d := RoomSpawnPlanner.plan_enemy(r, 2)
	assert_eq(d.enemy_id, "r5_e2", "spawn_idx threads through to id")

func test_plan_enemy_max_hp_matches_kind():
	# Pin that we go through EnemyData.make_new (so future stat changes
	# in EnemyData propagate without the planner having to re-pin them).
	var r := _make_standard_room(0, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_eq(d.max_hp, EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT))
	assert_eq(d.attack, EnemyData.base_attack_for(EnemyData.EnemyKind.DOG_KNIGHT))

# --- plan_powerup ----------------------------------------------------------

func test_plan_powerup_powerup_room_returns_type():
	var r := _make_powerup_room(2, "catnip")
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "catnip")

func test_plan_powerup_returns_each_seeded_type():
	# Locks the contract that whatever the generator seeded (via
	# DungeonGenerator's POWER_UP_TYPES pool) round-trips through the
	# planner unchanged.
	for t in ["catnip", "ale", "mushrooms"]:
		assert_eq(RoomSpawnPlanner.plan_powerup(_make_powerup_room(1, t)), t)

func test_plan_powerup_standard_room_returns_empty():
	# A standard room never has a power_up_type seeded by the generator,
	# but defensively reject even if some future code path leaks one in
	# — the planner's gate is room.type, not the field's truthiness.
	var r := _make_standard_room(3)
	r.power_up_type = "catnip"
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "", "non-powerup rooms return empty regardless of field")

func test_plan_powerup_boss_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(_make_boss_room(7)), "")

func test_plan_powerup_start_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(_make_start_room(0)), "")

func test_plan_powerup_null_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(null), "", "null room is safe no-op")

func test_plan_powerup_unknown_type_passes_through():
	# The planner does not validate against PowerUpEffect's known set;
	# the late gate is PowerUpEffect.make at pickup time. A stale-save
	# typo or a future-power-up id flows through as-is.
	var r := _make_powerup_room(1, "espresso")
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "espresso")

func test_plan_powerup_no_overlap_with_plan_enemy():
	# Pin that the two planner outputs are mutually exclusive per room:
	# a room either has an enemy or a power-up, never both. The future
	# spawner branches on which planner returned non-empty.
	var combat := _make_standard_room(1)
	assert_not_null(RoomSpawnPlanner.plan_enemy(combat))
	assert_eq(RoomSpawnPlanner.plan_powerup(combat), "")

	var powerup := _make_powerup_room(2, "ale")
	assert_null(RoomSpawnPlanner.plan_enemy(powerup))
	assert_eq(RoomSpawnPlanner.plan_powerup(powerup), "ale")

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

func _generate_dungeon_with_layout(seed: int = 1234) -> Array:
	# Returns [dungeon, layout] from the production generator + engine so the
	# multi-room tests cover the same code path as production. Seed is fixed so
	# the assertion shape (room types, ids) is deterministic.
	var d := DungeonGenerator.generate(seed)
	var layout := DungeonLayoutEngine.new().compute(d)
	return [d, layout]

# --- register_all_room_enemies (multi-room, issue #96) ---------------------

func test_register_all_room_enemies_returns_one_id_per_mob_across_rooms():
	# Core wiring (#372): every STANDARD + BOSS room mints one id PER mob in
	# its enemy_kinds list (from #371's RoomPopulationPlanner). Total ids
	# equals the sum of enemy_kinds sizes across all combat rooms; START +
	# POWERUP + BAR rooms contribute 0.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout)
	var expected_mob_count := 0
	for r in dungeon.rooms:
		if r.type == Room.TYPE_STANDARD or r.type == Room.TYPE_BOSS:
			expected_mob_count += r.enemy_kinds.size()
	assert_eq(ids.size(), expected_mob_count,
		"one enemy_id per mob across all combat rooms")

func test_register_all_room_enemies_assigns_spawn_position_from_layout():
	# Each spawned mob's spawn_position lands inside its room's world rect.
	# Single-mob rooms (count == 1) place the mob at the room center to
	# preserve pre-#372 behavior; multi-mob rooms spread within the rect.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type != Room.TYPE_STANDARD and r.type != Room.TYPE_BOSS:
			continue
		var records := planner.enemy_data_list_for_room(r.id)
		assert_gt(records.size(), 0, "combat room %d has planned data" % r.id)
		var rect: Rect2 = layout.room_rect_world(r.id)
		for data in records:
			assert_true(rect.has_point(data.spawn_position),
				"room %d spawn at %s lies in rect %s" % [r.id, str(data.spawn_position), str(rect)])
		if records.size() == 1:
			assert_eq(records[0].spawn_position, layout.room_center_world(r.id),
				"single-mob room %d preserves center placement" % r.id)

func test_register_all_room_enemies_skips_non_combat_rooms():
	# START and POWERUP rooms must not have a planned EnemyData — the
	# scene-tree spawner reads enemy_data_for_room as the gate for "should I
	# instantiate an enemy here?".
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type == Room.TYPE_START or r.type == Room.TYPE_POWERUP:
			assert_null(planner.enemy_data_for_room(r.id),
				"non-combat room %d (%s) has no planned enemy" % [r.id, r.type])

func test_register_all_room_enemies_marks_boss_room_with_is_boss():
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	var boss := planner.enemy_data_for_room(dungeon.boss_id)
	assert_not_null(boss, "boss room has a planned enemy")
	assert_true(boss.is_boss, "boss room enemy carries the is_boss flag")

func test_register_all_room_enemies_uses_stable_id_format():
	# enemy_id format remains "r{room_id}_e{spawn_idx}" — the wire layer's
	# OP_KILL packet and the per-room watcher's expected set both depend on
	# this format. A drift here would break remote-kill apply at the receiver.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type != Room.TYPE_STANDARD and r.type != Room.TYPE_BOSS:
			continue
		var data := planner.enemy_data_for_room(r.id)
		assert_eq(data.enemy_id, "r%d_e0" % r.id)

func test_register_all_room_enemies_registers_each_id_with_session():
	# Co-op path: every minted id is present in session.enemy_sync so the
	# remote-kill receive flow's apply_death finds it on the receiving client.
	var session := _make_session_with_lobby()
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout, session)
	for id in ids:
		assert_true(session.enemy_sync.is_alive(id),
			"session.enemy_sync knows about every planned id: %s" % id)

func test_register_all_room_enemies_null_session_still_returns_ids():
	# Solo path: session is null. The planner still mints and stores data so
	# the scene-tree spawner can instantiate the Enemy nodes; the wire layer's
	# empty-registry short-circuit keeps solo behavior unchanged.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout, null)
	assert_gt(ids.size(), 0, "solo path still mints ids")
	var boss := planner.enemy_data_for_room(dungeon.boss_id)
	assert_not_null(boss)

func test_register_all_room_enemies_idempotent_on_repeat_call():
	# A second call rebuilds the internal map from scratch but does not pollute
	# the session registry (register_enemy is idempotent). Mirrors the
	# scene-reload pattern that may double-fire register during the
	# advance_to->reload deprecation in #97.
	var session := _make_session_with_lobby()
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var first := planner.register_all_room_enemies(dungeon, layout, session)
	var before := session.enemy_sync.alive_count()
	var second := planner.register_all_room_enemies(dungeon, layout, session)
	assert_eq(session.enemy_sync.alive_count(), before,
		"no registry growth on repeat call")
	assert_eq(second.size(), first.size(),
		"second call still returns the full id list")

func test_register_all_room_enemies_null_dungeon_safe():
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(null, null)
	assert_eq(ids.size(), 0, "null dungeon is a safe no-op")

func test_enemy_data_for_room_unknown_id_returns_null():
	var planner := RoomSpawnPlanner.new()
	assert_null(planner.enemy_data_for_room(999),
		"unknown room id returns null before any planning")

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

# --- multi-mob fan-out (issue #372) ---------------------------------------

func _make_multi_room(room_id: int, kinds: Array) -> Room:
	# Helper for #372: a standard room with an explicit enemy_kinds list
	# (the data RoomPopulationPlanner produces). enemy_kind stays in place
	# (= kinds[0]) for the legacy single-mob callers.
	var r := Room.make(room_id, Room.TYPE_STANDARD)
	r.enemy_kinds = kinds
	r.enemy_kind = kinds[0]
	return r

func test_enemy_ids_for_multi_mob_room_returns_n_ids():
	# A standard room with 3 enemy_kinds yields three ids "r{id}_e0..e2".
	var room := _make_multi_room(4, [
		EnemyData.EnemyKind.ANGRY_PIGEON,
		EnemyData.EnemyKind.ROGUE_ROOMBA,
		EnemyData.EnemyKind.DOG_KNIGHT,
	])
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	assert_eq(ids.size(), 3)
	assert_eq(ids[0], "r4_e0")
	assert_eq(ids[1], "r4_e1")
	assert_eq(ids[2], "r4_e2")

func test_register_room_enemies_multi_mob_returns_one_record_per_kind():
	# register_room_enemies fans out N records, each with the matching kind
	# from enemy_kinds and a unique enemy_id.
	var session := _make_session_with_lobby()
	var room := _make_multi_room(3, [
		EnemyData.EnemyKind.ANGRY_PIGEON,
		EnemyData.EnemyKind.ROGUE_ROOMBA,
		EnemyData.EnemyKind.DOG_KNIGHT,
	])
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(spawned.size(), 3)
	assert_eq(spawned[0].enemy_id, "r3_e0")
	assert_eq(spawned[1].enemy_id, "r3_e1")
	assert_eq(spawned[2].enemy_id, "r3_e2")
	assert_eq(spawned[0].kind, EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(spawned[1].kind, EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_eq(spawned[2].kind, EnemyData.EnemyKind.DOG_KNIGHT)
	for d in spawned:
		assert_true(session.enemy_sync.is_alive(d.enemy_id),
			"each minted id is registered: %s" % d.enemy_id)

func test_register_all_room_enemies_fans_out_per_kind_with_distinct_positions():
	# Wire the multi-mob list through register_all_room_enemies: a room with
	# 3 enemy_kinds must yield 3 records exposed via enemy_data_list_for_room,
	# each with its own spread spawn_position.
	var dungeon := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var combat := _make_multi_room(1, [
		EnemyData.EnemyKind.ANGRY_PIGEON,
		EnemyData.EnemyKind.ROGUE_ROOMBA,
		EnemyData.EnemyKind.DOG_KNIGHT,
	])
	var boss := Room.make(2, Room.TYPE_BOSS)
	boss.enemy_kinds = [EnemyData.EnemyKind.DOG_KNIGHT]
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	start.connections = [1]
	combat.connections = [2]
	dungeon.add_room(start)
	dungeon.add_room(combat)
	dungeon.add_room(boss)
	dungeon.start_id = 0
	dungeon.boss_id = 2
	var layout := DungeonLayoutEngine.new().compute(dungeon)

	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	var records := planner.enemy_data_list_for_room(1)
	assert_eq(records.size(), 3, "fan-out: 3 records for 3 enemy_kinds")
	var seen_ids := {}
	var seen_positions := {}
	for d in records:
		seen_ids[d.enemy_id] = true
		seen_positions[d.spawn_position] = true
	assert_eq(seen_ids.size(), 3, "each record carries a unique enemy_id")
	assert_eq(seen_positions.size(), 3, "each record carries a distinct spawn_position")

func test_register_all_room_enemies_boss_room_still_single_record():
	# The boss room remains a single record with is_boss=true; the spread
	# call for count=1 places it at the room center (room_bounds is set so
	# the boss stays clamped inside its room).
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	var boss_records := planner.enemy_data_list_for_room(dungeon.boss_id)
	assert_eq(boss_records.size(), 1, "boss room yields exactly one record")
	assert_true(boss_records[0].is_boss)
	assert_eq(boss_records[0].spawn_position, layout.room_center_world(dungeon.boss_id),
		"boss spawns at the room center")

func test_register_all_room_enemies_non_combat_rooms_have_empty_list():
	# Power-up and start rooms expose an empty list (the spawner uses that as
	# the gate for "instantiate nothing combat-related here").
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type == Room.TYPE_START or r.type == Room.TYPE_POWERUP or r.type == Room.TYPE_BAR:
			assert_eq(planner.enemy_data_list_for_room(r.id).size(), 0,
				"non-combat room %d (%s) has no planned mobs" % [r.id, r.type])

func test_register_all_room_enemies_registers_every_minted_id_with_session():
	# Co-op: every fanned-out id is registered on enemy_sync so OP_KILL
	# packets converge at the receiver for every mob, not just the first.
	var session := _make_session_with_lobby()
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout, session)
	for id in ids:
		assert_true(session.enemy_sync.is_alive(id),
			"session.enemy_sync registered fanned-out id %s" % id)

# --- floor scaling ---------------------------------------------------------

func test_plan_enemy_floor_1_is_baseline():
	# Floor 1 means depth 0, so the scaling multipliers are all 1.0x and the
	# enemy's stats match the unscaled make_new output.
	var r := _make_standard_room(3, EnemyData.EnemyKind.ANGRY_PIGEON)
	var d := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	assert_eq(d.max_hp, EnemyData.base_max_hp_for(EnemyData.EnemyKind.ANGRY_PIGEON))
	assert_eq(d.attack, EnemyData.base_attack_for(EnemyData.EnemyKind.ANGRY_PIGEON))

func test_plan_enemy_higher_floor_boosts_hp_and_attack():
	# Per-floor scaling is monotonic — a deeper floor's enemy must have
	# strictly more hp and attack than the floor-1 version of the same kind.
	var r := _make_standard_room(3, EnemyData.EnemyKind.ANGRY_PIGEON)
	var f1 := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	var f5 := RoomSpawnPlanner.plan_enemy(r, 0, 5)
	assert_gt(f5.max_hp, f1.max_hp, "floor 5 standard enemy has more hp")
	assert_gt(f5.attack, f1.attack, "floor 5 standard enemy hits harder")

func test_plan_enemy_floor_scaling_stacks_on_boss_multipliers():
	# Floor scaling applies on top of the boss multipliers — a floor-5 boss
	# is meaningfully nastier than a floor-1 boss.
	var r := _make_boss_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var f1 := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	var f5 := RoomSpawnPlanner.plan_enemy(r, 0, 5)
	assert_gt(f5.max_hp, f1.max_hp)
	assert_gt(f5.attack, f1.attack)
	assert_gt(f5.defense, f1.defense, "boss defense scales too (boss has nonzero base)")

func test_plan_enemy_floor_scaling_boosts_rewards():
	# Stronger enemies pay better — xp/gold scale per floor so the run reward
	# keeps pace with the increased risk.
	var r := _make_standard_room(3, EnemyData.EnemyKind.ANGRY_PIGEON)
	var f1 := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	var f5 := RoomSpawnPlanner.plan_enemy(r, 0, 5)
	assert_gt(f5.xp_reward, f1.xp_reward)
	assert_gt(f5.gold_reward, f1.gold_reward)

func test_plan_enemy_hp_equals_max_hp_after_floor_scaling():
	# After scaling bumps max_hp, the enemy spawns at full health — no off-by-
	# one where max_hp scaled and hp didn't.
	var r := _make_boss_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r, 0, 4)
	assert_eq(d.hp, d.max_hp)

func test_plan_enemy_floor_default_is_one():
	# Backward-compat: callers that don't yet pass floor_number get the
	# baseline (floor-1) behavior — pinned so a future signature change
	# doesn't silently shift existing call sites' scaling.
	var r := _make_standard_room(3, EnemyData.EnemyKind.ANGRY_PIGEON)
	var d_default := RoomSpawnPlanner.plan_enemy(r)
	var d_floor1 := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	assert_eq(d_default.max_hp, d_floor1.max_hp)
	assert_eq(d_default.attack, d_floor1.attack)

func test_register_all_room_enemies_threads_floor_into_scaling():
	# The dungeon-load entry point must forward floor_number into plan_enemy so
	# every spawned enemy carries the floor's scaling.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner_f1 := RoomSpawnPlanner.new()
	planner_f1.register_all_room_enemies(dungeon, layout, null, 1)
	var planner_f5 := RoomSpawnPlanner.new()
	planner_f5.register_all_room_enemies(dungeon, layout, null, 5)
	var boss_f1 := planner_f1.enemy_data_for_room(dungeon.boss_id)
	var boss_f5 := planner_f5.enemy_data_for_room(dungeon.boss_id)
	assert_gt(boss_f5.max_hp, boss_f1.max_hp,
		"floor-5 boss is tougher than floor-1 boss after register_all")

# --- party-size scaling (issue #324) ---------------------------------------

func test_register_room_enemies_threads_party_size_into_boss_stats():
	# Locks the contract: the planner reads party size from the session and
	# threads it into BossScaling. A 3-member session must produce a boss
	# with stats matching BossScaling.compute_boss_stats(..., party_size=3,
	# avg_party_level=1.0 (default-character level), floor_baseline=3 (floor 1)).
	var session := _make_session_with_n_members(3)
	var room := _make_boss_room(7, EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room, 1)
	var expected := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
	}, 1, 3, 1.0, BossScaling.baseline_level_for_floor(1))
	assert_eq(spawned[0].max_hp, expected["hp"])
	assert_eq(spawned[0].attack, expected["attack"])

func test_register_all_room_enemies_threads_party_size():
	# The dungeon-load entry point also derives party_size from the session,
	# so a 4-player session has bigger boss hp than a solo session for the
	# same dungeon + floor.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var solo_session := _make_session_with_n_members(1)
	var quad_session := _make_session_with_n_members(4)
	var planner_solo := RoomSpawnPlanner.new()
	planner_solo.register_all_room_enemies(dungeon, layout, solo_session, 1)
	var planner_quad := RoomSpawnPlanner.new()
	planner_quad.register_all_room_enemies(dungeon, layout, quad_session, 1)
	var boss_solo := planner_solo.enemy_data_for_room(dungeon.boss_id)
	var boss_quad := planner_quad.enemy_data_for_room(dungeon.boss_id)
	assert_gt(boss_quad.max_hp, boss_solo.max_hp,
		"4-player boss hp must exceed solo boss hp at the same floor")

func test_register_room_enemies_null_session_is_solo_scaled():
	# Solo / null-session path: planner must not crash, and the boss it
	# returns must match party_size=1 (not 0 / not table-out-of-bounds) and
	# avg_party_level=1.0 (the empty-party fallback so a missing session
	# doesn't silently zero out the level mult).
	var room := _make_boss_room(7, EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spawned := RoomSpawnPlanner.register_room_enemies(null, room, 1)
	var expected := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
	}, 1, 1, 1.0, BossScaling.baseline_level_for_floor(1))
	assert_eq(spawned[0].max_hp, expected["hp"])

# --- new enemy roster (issue #154) -----------------------------------------

func test_boss_enemy_name_matches_boss_roster_floor_1():
	# Slice #301 (PRD #297): the boss name now reads from BossRoster
	# (stamped on Room.boss_display_name by the generator). Default
	# floor=1 means every boss is the Vacuum.
	var expected: String = BossRoster.boss_for_floor(1).display_name
	for seed in range(1, 30):
		var dungeon := DungeonGenerator.generate(seed)
		var boss_room: Room = dungeon.rooms[dungeon.boss_id]
		var boss_data := RoomSpawnPlanner.plan_enemy(boss_room)
		assert_eq(boss_data.enemy_name, expected,
			"seed %d boss name should match BossRoster (floor 1: %s)" % [seed, expected])

func test_standard_rooms_never_emit_old_kind_names():
	# None of the placeholder names (Slime / Bat / Rat) appear in the
	# pool the generator draws standard rooms from.
	var old_names := ["Slime", "Bat", "Rat"]
	for seed in range(1, 30):
		var dungeon := DungeonGenerator.generate(seed)
		for room in dungeon.rooms:
			if room.type != Room.TYPE_STANDARD:
				continue
			var data := RoomSpawnPlanner.plan_enemy(room)
			assert_false(old_names.has(data.enemy_name),
				"seed %d room %d emitted old name %s" % [seed, room.id, data.enemy_name])

func test_all_five_kinds_reachable_in_standard_pool():
	# Probabilistic coverage: across many seeded dungeons, every one of the
	# 5 new display names appears at least once as a standard-room enemy.
	# The generator picks uniformly from STANDARD_ENEMY_KINDS, so 30 seeds
	# x ~5 standard rooms each (~150 draws) gives effectively zero chance
	# of a missed kind unless the pool itself is wrong.
	var seen := {}
	for seed in range(1, 60):
		var dungeon := DungeonGenerator.generate(seed)
		for room in dungeon.rooms:
			if room.type != Room.TYPE_STANDARD:
				continue
			var data := RoomSpawnPlanner.plan_enemy(room)
			seen[data.enemy_name] = true
	for expected in ["Angry Pigeon", "Rogue Roomba", "Dog Knight", "Catnip Dealer", "Haunted Spray Bottle"]:
		assert_true(seen.has(expected), "kind %s appeared in standard pool" % expected)

# --- mob level (PRD #376 / issue #377) -------------------------------------

func test_plan_enemy_sets_level():
	# Standard floor-1 Dog Knight: per-kind offset 4 + floor baseline 0 = 4.
	var r := _make_standard_room(7, EnemyData.EnemyKind.DOG_KNIGHT)
	var d := RoomSpawnPlanner.plan_enemy(r, 0, 1)
	assert_eq(d.level, 4)
