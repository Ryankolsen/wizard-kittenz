extends GutTest

# Unit tests for GwendolynFloorWipe (issue #478). Pure filtering logic —
# given every enemy currently on the floor, returns the subset that the
# Summon Gwendolyn cast payoff should kill (everything except the boss).
# Testable without booting a scene, same pattern as
# test_kill_reward_router.gd's pure-data branch tests.

func _make_enemy(is_boss: bool = false) -> EnemyData:
	var e := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	e.is_boss = is_boss
	return e

func test_non_boss_kills_excludes_boss_includes_others():
	var boss := _make_enemy(true)
	var mob_a := _make_enemy(false)
	var mob_b := _make_enemy(false)
	var result: Array = GwendolynFloorWipe.non_boss_kills([boss, mob_a, mob_b])
	assert_eq(result.size(), 2, "boss excluded, both mobs included")
	assert_true(result.has(mob_a))
	assert_true(result.has(mob_b))
	assert_false(result.has(boss))

func test_non_boss_kills_empty_list_is_safe_no_op():
	var result: Array = GwendolynFloorWipe.non_boss_kills([])
	assert_eq(result.size(), 0, "empty floor yields no kills")

func test_non_boss_kills_boss_only_floor_yields_zero_kills():
	var boss := _make_enemy(true)
	var result: Array = GwendolynFloorWipe.non_boss_kills([boss])
	assert_eq(result.size(), 0, "boss-only floor: zero kills, boss survives")

func test_non_boss_kills_null_entries_are_skipped():
	var mob := _make_enemy(false)
	var result: Array = GwendolynFloorWipe.non_boss_kills([null, mob])
	assert_eq(result.size(), 1, "null entries filtered out, not crashing")
	assert_true(result.has(mob))

# --- Co-op XP split for a floor-wipe kill list (issue #478 AC) --------------
# Reuses the CoopSession/LobbyState fixtures and xp_broadcaster.xp_awarded
# signal-capture pattern from test_kill_reward_router.gd to pin that routing
# a floor-wipe's kill list through KillRewardRouter.route_kill splits XP
# exactly like a normal multi-kill sequence would.

func _make_character(level: int = 1) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = level
	return c

func _make_lobby(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	d.add_room(boss)
	d.boss_id = 1
	return d

func _make_enemy_with_xp(xp_reward: int, is_boss: bool = false) -> EnemyData:
	var e := _make_enemy(is_boss)
	e.xp_reward = xp_reward
	return e

func test_floor_wipe_kill_list_splits_xp_like_a_normal_multi_kill_sequence():
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	var boss := _make_enemy_with_xp(999, true)
	var mob_a := _make_enemy_with_xp(10)
	var mob_b := _make_enemy_with_xp(20)
	var kill_list: Array = GwendolynFloorWipe.non_boss_kills([boss, mob_a, mob_b])
	assert_eq(kill_list.size(), 2, "boss excluded from the floor-wipe kill list")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	for enemy_data in kill_list:
		KillRewardRouter.route_kill(c, enemy_data, session, "u1", null, null, null, null, null, null, 0, null, true)
	# 2 kills * 2 party members = 4 emissions; each kill's XP is floor-split.
	assert_eq(emissions.size(), 4, "xp_broadcaster fired once per party member per kill")
	assert_eq(c.xp, 5 + 10, "u1 received its split share of both kills (10/2 + 20/2)")
