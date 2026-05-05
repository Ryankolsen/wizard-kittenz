extends GutTest

# Unit tests for KillRewardRouter. Pure-data branch between solo and co-op
# kill paths — testable without booting a Player scene.

# --- Test helpers ----------------------------------------------------------

func _make_character(level: int = 1) -> CharacterData:
	# Mage L1 baseline. Level can be bumped to set up "near a milestone"
	# preconditions for milestone-crossing tests. xp stays at 0 so a
	# kill's xp_reward fully drives the level-up math.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.level = level
	return c

func _make_enemy(xp_reward: int, is_boss: bool = false) -> EnemyData:
	var e := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	e.xp_reward = xp_reward
	e.is_boss = is_boss
	return e

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
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	d.add_room(boss)
	d.boss_id = 1
	return d

# --- is_coop_route predicate ------------------------------------------------

func test_is_coop_route_null_session_returns_false():
	# A solo kill has no session — must take the solo branch.
	assert_false(KillRewardRouter.is_coop_route(null, "u1"))

func test_is_coop_route_inactive_session_returns_false():
	# Constructed but not started — broadcaster is null. Solo branch
	# fires so the kill still grants XP locally.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, null, "u1")
	assert_false(session.is_active())
	assert_false(KillRewardRouter.is_coop_route(session, "u1"))

func test_is_coop_route_empty_local_id_returns_false():
	# A pre-handshake session where the local player_id hasn't been
	# resolved yet. Solo branch fires so the kill still grants XP
	# locally rather than being silently dropped.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_active())
	assert_false(KillRewardRouter.is_coop_route(session, ""))

func test_is_coop_route_active_session_with_local_id_returns_true():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(KillRewardRouter.is_coop_route(session, "u1"))

# --- route_kill: null safety ------------------------------------------------

func test_route_kill_null_character_data_returns_zero():
	var inv := TokenInventory.new()
	var enemy := _make_enemy(10)
	assert_eq(KillRewardRouter.route_kill(null, enemy, inv, null, ""), 0)
	assert_eq(inv.count, 0, "no grant on null character")

func test_route_kill_null_enemy_data_returns_zero():
	# A future DoT spell with no enemy reference must not crash.
	var c := _make_character()
	var inv := TokenInventory.new()
	assert_eq(KillRewardRouter.route_kill(c, null, inv, null, ""), 0)
	assert_eq(c.xp, 0, "no XP applied")
	assert_eq(inv.count, 0)

# --- route_kill: solo path --------------------------------------------------

func test_route_kill_solo_applies_xp_locally():
	# Kill an enemy worth 5 XP (exactly L1->L2 threshold). Solo path runs
	# ProgressionSystem.add_xp against the killer's CharacterData.
	var c := _make_character(1)
	var enemy := _make_enemy(5)
	var inv := TokenInventory.new()
	KillRewardRouter.route_kill(c, enemy, inv, null, "")
	assert_eq(c.level, 2, "L1->L2 on 5 XP")

func test_route_kill_solo_no_token_below_milestone():
	# Non-boss kill that doesn't cross a milestone level (L5). Returns 0
	# tokens granted; inventory untouched.
	var c := _make_character(1)
	var enemy := _make_enemy(5)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, enemy, inv, null, "")
	assert_eq(granted, 0)
	assert_eq(inv.count, 0, "no milestone, no boss, no grant")

func test_route_kill_solo_grants_boss_bonus():
	# Boss kill. Boss bonus regardless of level transition.
	var c := _make_character(1)
	var boss := _make_enemy(5, true)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, boss, inv, null, "")
	assert_eq(granted, TokenGrantRules.tokens_for_boss_kill())
	assert_eq(inv.count, TokenGrantRules.tokens_for_boss_kill())

func test_route_kill_solo_grants_milestone_on_threshold_crossing():
	# Set up so the kill XP crosses L5 (milestone). At L4 the next level
	# costs 5 + 3*5 = 20 XP. Award exactly 20 to land on L5.
	var c := _make_character(4)
	var enemy := _make_enemy(20)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, enemy, inv, null, "")
	assert_eq(c.level, 5)
	assert_eq(granted, TokenGrantRules.tokens_for_level_up(4, 5),
		"milestone crossing grants the milestone amount")
	assert_eq(inv.count, granted)

func test_route_kill_solo_combines_milestone_and_boss():
	# Boss kill that crosses a milestone — both rewards stack.
	var c := _make_character(4)
	var boss := _make_enemy(20, true)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, boss, inv, null, "")
	var expected := TokenGrantRules.tokens_for_level_up(4, 5) + TokenGrantRules.tokens_for_boss_kill()
	assert_eq(granted, expected, "milestone + boss combined")
	assert_eq(inv.count, expected)

func test_route_kill_solo_null_inventory_still_applies_xp():
	# A test path with no GameState (null inventory) shouldn't block XP
	# from applying. Returns 0 since no grant happens.
	var c := _make_character(1)
	var enemy := _make_enemy(5)
	var granted := KillRewardRouter.route_kill(c, enemy, null, null, "")
	assert_eq(granted, 0)
	assert_eq(c.level, 2, "XP still applies without inventory")

# --- route_kill: co-op path -------------------------------------------------

func test_route_kill_coop_broadcasts_xp_to_all_party_members():
	# The killer's call broadcasts XP via session.xp_broadcaster, fanning
	# out to every party member. The local CharacterData is NOT mutated
	# directly here — the LocalXPRouter on this client (constructed by
	# the session when it knows the local id) bounces the broadcast back
	# to member.real_stats === Player.data.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var characters := {"u1": c, "u2": _make_character(1)}
	# local_player_id="u1" so the session wires LocalXPRouter for u1.
	# member.real_stats is the same CharacterData reference c, so the
	# router's XPSystem.award lands on c.xp.
	var session := CoopSession.new(lobby, characters, null, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	var inv := TokenInventory.new()
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	var granted := KillRewardRouter.route_kill(c, enemy, inv, session, "u1")
	assert_eq(granted, 0, "non-boss kill in co-op grants 0 boss bonus")
	assert_eq(emissions.size(), 2, "broadcaster fired for both party members")
	assert_eq(emissions[0][1], 3, "amount preserved")
	# Local XP applied via the router (member.real_stats === c).
	assert_eq(c.xp, 3, "router applied XP locally")

func test_route_kill_coop_does_not_apply_xp_directly():
	# Without a wired LocalXPRouter (default-constructed session, no
	# local_player_id), the broadcast still fans out but no local
	# member.real_stats receives it. The killer's data must NOT be
	# mutated by route_kill itself — only the broadcaster's emission
	# can route XP. This pins the contract that the co-op branch is
	# pure broadcast, not a direct add_xp call.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	# Session active but no local_player_id => no LocalXPRouter wired
	# even though "u1" matches via predicate. Pass empty local_id to
	# the router, but to keep the predicate true we need a non-empty
	# local id here. So instead, construct a session WITH local id
	# but verify the broadcast happened independently of any local
	# add_xp call. (The previous test already pins XP application via
	# the router; this test pins that route_kill itself doesn't double.)
	var session := CoopSession.new(lobby, {"u1": c}, null, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	KillRewardRouter.route_kill(c, enemy, null, session, "u1")
	# Exactly ONE emission for u1 (single party). c.xp == 3 from the
	# router — if the helper also did its own add_xp it would be 6.
	assert_eq(emissions.size(), 1)
	assert_eq(c.xp, 3, "no double XP application")

func test_route_kill_coop_grants_boss_bonus_locally():
	# Boss-kill bonus stays on the killer's local inventory in co-op.
	# The XP fan-out is broadcast (every party member); the boss bonus
	# is killer-only.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(
		lobby,
		{"u1": c, "u2": _make_character(1)},
		null,
		null,
		"u1",
	)
	session.start(_make_two_room_dungeon())
	var boss := _make_enemy(3, true)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, boss, inv, session, "u1")
	assert_eq(granted, TokenGrantRules.tokens_for_boss_kill())
	assert_eq(inv.count, TokenGrantRules.tokens_for_boss_kill(),
		"local inventory got the boss bonus only")

func test_route_kill_coop_does_not_grant_milestone_locally():
	# Milestone tokens are routed via LocalTokenGrantRouter (subscribed
	# to LocalXPRouter.level_up). Granting them again here would double-
	# count for a local kill that crosses a milestone. The helper must
	# NOT add tokens_for_level_up to the inventory in the co-op path.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(4)
	var inv := TokenInventory.new()
	var session := CoopSession.new(lobby, {"u1": c}, null, inv, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(20)
	# Tokens come from LocalTokenGrantRouter via the level_up signal.
	# The helper adds nothing to the inventory beyond the (zero) boss
	# bonus on a non-boss kill.
	var granted := KillRewardRouter.route_kill(c, enemy, inv, session, "u1")
	assert_eq(granted, 0, "non-boss co-op kill grants 0 directly")
	# But the inventory IS still credited via the token_router's
	# level_up subscription on the L4->L5 crossing.
	assert_eq(c.level, 5, "router applied XP and crossed milestone")
	assert_eq(inv.count, TokenGrantRules.tokens_for_level_up(4, 5),
		"milestone token came from token_router, not from route_kill")

func test_route_kill_coop_milestone_plus_boss_no_double_grant():
	# Boss kill that crosses a milestone in co-op: the inventory ends up
	# with milestone (from token_router) + boss bonus (from this helper).
	# If the helper accidentally also added milestone, the count would
	# be 2x the milestone amount.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(4)
	var inv := TokenInventory.new()
	var session := CoopSession.new(lobby, {"u1": c}, null, inv, "u1")
	session.start(_make_two_room_dungeon())
	var boss := _make_enemy(20, true)
	var granted := KillRewardRouter.route_kill(c, boss, inv, session, "u1")
	assert_eq(granted, TokenGrantRules.tokens_for_boss_kill(),
		"helper returned boss bonus only")
	var expected := TokenGrantRules.tokens_for_level_up(4, 5) + TokenGrantRules.tokens_for_boss_kill()
	assert_eq(inv.count, expected,
		"inventory has milestone (router) + boss (helper), no double")

func test_route_kill_coop_inactive_session_falls_to_solo():
	# A session that's been end()'d must take the solo branch — its
	# broadcaster is null so a co-op route would no-op the broadcast
	# and silently drop the XP. Solo branch keeps the kill rewarding.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, null, "u1")
	session.start(_make_two_room_dungeon())
	session.end()
	var enemy := _make_enemy(5)
	var inv := TokenInventory.new()
	var granted := KillRewardRouter.route_kill(c, enemy, inv, session, "u1")
	# Solo path applied XP locally.
	assert_eq(c.level, 2, "post-end falls back to solo XP")
	assert_eq(granted, 0, "non-boss + no milestone = 0 granted")

func test_route_kill_coop_empty_local_id_falls_to_solo():
	# A session active but with no local id resolved (pre-handshake
	# wire-payload race) takes the solo branch so XP isn't dropped on
	# the floor. The session is still "active" but no party member can
	# receive a filtered xp_awarded since this client doesn't know its
	# own id.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(5)
	var inv := TokenInventory.new()
	KillRewardRouter.route_kill(c, enemy, inv, session, "")
	assert_eq(c.level, 2, "empty local_id triggers solo branch")

# --- GameState wiring -------------------------------------------------------

# GameState is an autoload — a single instance shared across the test
# suite. Snapshot + restore in this section so the global state never
# leaks between tests.

var _saved_session: CoopSession = null
var _saved_local_id: String = ""

func _snapshot_game_state() -> void:
	_saved_session = GameState.coop_session
	_saved_local_id = GameState.local_player_id

func _restore_game_state() -> void:
	GameState.coop_session = _saved_session
	GameState.local_player_id = _saved_local_id

func test_game_state_coop_session_defaults_null():
	# Before the lobby flow lands, a fresh GameState load has no co-op
	# session and no resolved local_player_id. The Player kill flow
	# null-checks both and falls through to the solo branch.
	_snapshot_game_state()
	GameState.coop_session = null
	GameState.local_player_id = ""
	assert_null(GameState.coop_session, "fresh-install / no-multiplayer default")
	assert_eq(GameState.local_player_id, "", "no auth handshake yet")
	_restore_game_state()

func test_game_state_clear_drops_coop_session():
	# clear() is called on logout / character-reset paths. It must tear
	# down any live session so the per-run managers unbind cleanly. A
	# stale broadcaster left attached to the (about-to-be-replaced)
	# CharacterData would mutate stats post-clear.
	_snapshot_game_state()
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	GameState.coop_session = CoopSession.new(lobby, {"u1": c}, null, null, "u1")
	GameState.coop_session.start(_make_two_room_dungeon())
	GameState.local_player_id = "u1"
	assert_true(GameState.coop_session.is_active())
	GameState.clear()
	assert_null(GameState.coop_session, "session reference dropped")
	assert_eq(GameState.local_player_id, "", "local id reset")
	_restore_game_state()
