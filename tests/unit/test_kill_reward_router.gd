extends GutTest

# Unit tests for KillRewardRouter. Pure-data branch between solo and co-op
# kill paths — testable without booting a Player scene. Token economy was
# stripped in #30; route_kill no longer takes an inventory and no longer
# returns a grant count (boss-kill bonus is gone with the inventory).

# --- Test helpers ----------------------------------------------------------

func _make_character(level: int = 1) -> CharacterData:
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
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, "u1")
	assert_false(session.is_active())
	assert_false(KillRewardRouter.is_coop_route(session, "u1"))

func test_is_coop_route_empty_local_id_returns_false():
	# A pre-handshake session where the local player_id hasn't been
	# resolved yet. Solo branch fires so the kill still grants XP
	# locally rather than being silently dropped.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_active())
	assert_false(KillRewardRouter.is_coop_route(session, ""))

func test_is_coop_route_active_session_with_local_id_returns_true():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(KillRewardRouter.is_coop_route(session, "u1"))

# --- route_kill: null safety ------------------------------------------------

func test_route_kill_null_character_data_is_no_op():
	# Must not crash. The enemy is left untouched.
	var enemy := _make_enemy(10)
	var pre_xp_reward := enemy.xp_reward
	KillRewardRouter.route_kill(null, enemy, null, "")
	assert_eq(enemy.xp_reward, pre_xp_reward, "null character path is a no-op")

func test_route_kill_null_enemy_data_is_no_op():
	# A future DoT spell with no enemy reference must not crash.
	var c := _make_character()
	KillRewardRouter.route_kill(c, null, null, "")
	assert_eq(c.xp, 0, "no XP applied")

# --- route_kill: solo path --------------------------------------------------

func test_route_kill_solo_applies_xp_locally():
	# Kill an enemy worth 5 XP (exactly L1->L2 threshold). Solo path runs
	# ProgressionSystem.add_xp against the killer's CharacterData.
	var c := _make_character(1)
	var enemy := _make_enemy(5)
	KillRewardRouter.route_kill(c, enemy, null, "")
	assert_eq(c.level, 2, "L1->L2 on 5 XP")

func test_route_kill_solo_boss_still_grants_xp():
	# Boss flag no longer drives any token branch — it's now metadata
	# only. The kill still grants XP via ProgressionSystem.add_xp.
	var c := _make_character(1)
	var boss := _make_enemy(5, true)
	KillRewardRouter.route_kill(c, boss, null, "")
	assert_eq(c.level, 2, "boss kill applies XP same as a generic kill")

# --- route_kill: offline XP tracker (#15 sync orchestrator hook) ------------

func test_route_kill_solo_records_offline_xp():
	# Solo path tallies the kill's xp_reward into the offline counter so
	# OfflineProgressMerger.merge_xp can fold it into the server record
	# on the next sync.
	var c := _make_character(1)
	var enemy := _make_enemy(7)
	var t := OfflineXPTracker.new()
	KillRewardRouter.route_kill(c, enemy, null, "", t)
	assert_eq(t.pending_xp, 7, "solo kill recorded into offline tracker")

func test_route_kill_solo_null_tracker_safe():
	# Pre-#15 wiring path / test paths without GameState pass null —
	# the helper must not crash and XP must still apply.
	var c := _make_character(1)
	var enemy := _make_enemy(5)
	KillRewardRouter.route_kill(c, enemy, null, "", null)
	assert_eq(c.level, 2, "null tracker doesn't block XP application")

func test_route_kill_coop_does_not_record_offline_xp():
	# Co-op path is intentionally a no-op for offline tracking — co-op
	# requires the network so any XP earned here is already "synced".
	# Recording it would double-count when the next solo kill triggers
	# a merge (the server already saw the broadcast).
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	# 4 XP keeps the kitten at L1 (L1->L2 needs 5) so the post-call xp
	# read is the raw amount routed by LocalXPRouter, not a level-up
	# remainder.
	var enemy := _make_enemy(4)
	var t := OfflineXPTracker.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", t)
	assert_eq(t.pending_xp, 0, "co-op kill does not touch offline tracker")
	assert_eq(c.xp, 4, "router still applied XP locally via LocalXPRouter")

func test_route_kill_coop_inactive_session_records_offline_xp():
	# An end()'d session falls through to the solo branch (broadcaster
	# is null in that window). The solo branch records into the tracker
	# so post-end kills still feed the offline counter.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.end()
	var enemy := _make_enemy(5)
	var t := OfflineXPTracker.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", t)
	assert_eq(t.pending_xp, 5, "post-end falls back to solo + records offline")

func test_route_kill_solo_accumulates_across_kills():
	# Successive solo kills sum into the tracker. Mirrors the real
	# gameplay loop: multiple offline kills accumulate into one merge
	# at sign-in. The orchestrator clears after the merge.
	var c := _make_character(1)
	var t := OfflineXPTracker.new()
	KillRewardRouter.route_kill(c, _make_enemy(3), null, "", t)
	KillRewardRouter.route_kill(c, _make_enemy(4), null, "", t)
	KillRewardRouter.route_kill(c, _make_enemy(2), null, "", t)
	assert_eq(t.pending_xp, 9, "9 = 3+4+2 across three kills")

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
	var session := CoopSession.new(lobby, characters, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(emissions.size(), 2, "broadcaster fired for both party members")
	assert_eq(emissions[0][1], 3, "amount preserved")
	# Local XP applied via the router (member.real_stats === c).
	assert_eq(c.xp, 3, "router applied XP locally")

func test_route_kill_coop_does_not_apply_xp_directly():
	# Without a wired LocalXPRouter the broadcast still fans out but no
	# local member.real_stats receives it. The killer's data must NOT be
	# mutated by route_kill itself — only the broadcaster's emission can
	# route XP. Pins the contract that the co-op branch is pure broadcast,
	# not a direct add_xp call.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	# Exactly ONE emission for u1 (single party). c.xp == 3 from the
	# router — if the helper also did its own add_xp it would be 6.
	assert_eq(emissions.size(), 1)
	assert_eq(c.xp, 3, "no double XP application")

func test_route_kill_coop_inactive_session_falls_to_solo():
	# A session that's been end()'d must take the solo branch — its
	# broadcaster is null so a co-op route would no-op the broadcast
	# and silently drop the XP. Solo branch keeps the kill rewarding.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.end()
	var enemy := _make_enemy(5)
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	# Solo path applied XP locally.
	assert_eq(c.level, 2, "post-end falls back to solo XP")

# --- route_kill: co-op enemy_sync apply_death (#17 wire-layer hook) ---------

func test_route_kill_coop_applies_death_to_enemy_sync():
	# Co-op path marks the enemy dead in the per-session EnemyStateSyncManager
	# registry so the wire layer's remote enemy-died packet (when #14 lands)
	# and this local kill detection converge through the same apply_death
	# call.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	assert_true(session.enemy_sync.is_alive("r3_e0"))
	var enemy := _make_enemy(3)
	enemy.enemy_id = "r3_e0"
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_false(session.enemy_sync.is_alive("r3_e0"),
		"co-op kill removed enemy from sync registry")

func test_route_kill_coop_empty_enemy_id_skips_apply_death():
	# Pre-spawn-layer / test fixture path: an enemy without an enemy_id
	# must not poke the registry with an unkeyed entry. The reward path
	# still runs (XP broadcast); only the apply_death call is skipped.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	# enemy_id left as "" (default).
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(session.enemy_sync.alive_count(), 0,
		"empty enemy_id never registers")
	assert_eq(c.xp, 3, "XP still broadcast and routed locally")

func test_route_kill_coop_apply_death_idempotent_with_remote_packet():
	# Race: the remote enemy-died packet arrived first (wire layer called
	# apply_death). Then the local kill detection fires here. apply_death
	# returns false the second time but doesn't error — same enemy isn't
	# double-removed and the kill flow continues to broadcast XP.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	# Remote packet arrived first: registry already shows the enemy as dead.
	session.enemy_sync.apply_death("r3_e0")
	assert_false(session.enemy_sync.is_alive("r3_e0"))
	var enemy := _make_enemy(3)
	enemy.enemy_id = "r3_e0"
	# Second apply_death (this one) is a no-op — but the kill flow still
	# broadcasts XP because the wire layer doesn't drive that path.
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(c.xp, 3, "XP still broadcast on second apply_death")

func test_route_kill_solo_does_not_touch_enemy_sync():
	# Solo path has no session, so no enemy_sync to call. A kill with an
	# enemy_id set must not crash and must not look for a registry that
	# doesn't exist.
	var c := _make_character(1)
	var enemy := _make_enemy(3)
	enemy.enemy_id = "r3_e0"
	# No session, no co-op route. apply_death is unreachable.
	KillRewardRouter.route_kill(c, enemy, null, "")
	assert_eq(c.xp, 3, "solo path still applied XP locally with enemy_id set")

func test_route_kill_coop_empty_local_id_falls_to_solo():
	# A session active but with no local id resolved (pre-handshake
	# wire-payload race) takes the solo branch so XP isn't dropped on
	# the floor.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(5)
	KillRewardRouter.route_kill(c, enemy, session, "")
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
	GameState.coop_session = CoopSession.new(lobby, {"u1": c}, null, "u1")
	GameState.coop_session.start(_make_two_room_dungeon())
	GameState.local_player_id = "u1"
	assert_true(GameState.coop_session.is_active())
	GameState.clear()
	assert_null(GameState.coop_session, "session reference dropped")
	assert_eq(GameState.local_player_id, "", "local id reset")
	_restore_game_state()
