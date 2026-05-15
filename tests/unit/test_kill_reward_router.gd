extends GutTest

# Unit tests for KillRewardRouter. Pure-data branch between solo and co-op
# kill paths — testable without booting a Player scene. Token economy was
# stripped in #30; route_kill no longer takes an inventory and no longer
# returns a grant count (boss-kill bonus is gone with the inventory).

# Test double for NakamaLobby that records calls to send_kill_async
# without touching a real socket. Lets the lobby-param tests pin the
# wire-send contract without booting the wire layer.
class _RecordingLobby:
	extends NakamaLobby
	var sent_kills: Array = []
	func send_kill_async(enemy_id: String, killer_id: String, xp_value: int) -> void:
		sent_kills.append([enemy_id, killer_id, xp_value])

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
	# Kill an enemy worth exactly the L1->L2 threshold of XP. Solo path runs
	# ProgressionSystem.add_xp against the killer's CharacterData.
	var c := _make_character(1)
	var enemy := _make_enemy(ProgressionSystem.xp_to_next_level(1))
	KillRewardRouter.route_kill(c, enemy, null, "")
	assert_eq(c.level, 2, "L1->L2 on threshold XP")

func test_route_kill_solo_boss_still_grants_xp():
	# Boss flag no longer drives any token branch — it's now metadata
	# only. The kill still grants XP via ProgressionSystem.add_xp.
	var c := _make_character(1)
	var boss := _make_enemy(ProgressionSystem.xp_to_next_level(1), true)
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
	var enemy := _make_enemy(ProgressionSystem.xp_to_next_level(1))
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
	#
	# PRD #52 party split: a 2-player party gets floor(xp_reward / 2) per
	# member, not the full reward.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var characters := {"u1": c, "u2": _make_character(1)}
	var session := CoopSession.new(lobby, characters, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(10)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(emissions.size(), 2, "broadcaster fired for both party members")
	assert_eq(emissions[0][1], 5, "amount split floor(10/2) per member")
	assert_eq(c.xp, 5, "router applied per-player share locally")

func test_route_kill_coop_three_player_party_floor_divides_xp():
	# PRD #52 AC: 100 XP / 3 players = 33 each (floor divide).
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
		["u3", "C", "Thief"],
	])
	var c := _make_character(1)
	var characters := {
		"u1": c,
		"u2": _make_character(1),
		"u3": _make_character(1),
	}
	var session := CoopSession.new(lobby, characters, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(100)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(emissions.size(), 3, "fan-out to all three players")
	for e in emissions:
		assert_eq(e[1], 33, "100 / 3 floors to 33")
	assert_eq(c.xp, 33, "router applied per-player share locally")

func test_route_kill_coop_single_player_party_keeps_full_xp():
	# PRD #52 AC: 1-player co-op session keeps the full reward
	# (party_size == 1 → no split).
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(20)
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(c.xp, 20, "solo-coop kill keeps full reward")

func test_xp_per_player_pure_helper():
	# Pure split helper — testable without booting a session.
	assert_eq(KillRewardRouter.xp_per_player(100, 3), 33, "floor(100/3)")
	assert_eq(KillRewardRouter.xp_per_player(10, 2), 5, "even split")
	assert_eq(KillRewardRouter.xp_per_player(20, 1), 20, "party_size 1 returns full")
	assert_eq(KillRewardRouter.xp_per_player(20, 0), 20, "defensive: party_size 0 returns full")
	assert_eq(KillRewardRouter.xp_per_player(2, 3), 0, "tiny reward floors to 0")

func test_route_kill_coop_two_player_wire_send_uses_split():
	# PRD #52 AC: the wire packet carries the per-player share so the
	# receiver's RemoteKillApplier can fan out the same per-player amount
	# without re-deriving party_size on its end. 10 XP / 2 = 5 on the wire.
	var lobby_state := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(10)
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 1)
	assert_eq(lobby.sent_kills[0][2], 5, "wire xp carries per-player share, not raw reward")

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
	var enemy := _make_enemy(ProgressionSystem.xp_to_next_level(1))
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
	var enemy := _make_enemy(ProgressionSystem.xp_to_next_level(1))
	KillRewardRouter.route_kill(c, enemy, session, "")
	assert_eq(c.level, 2, "empty local_id triggers solo branch")

# --- route_kill: wire send (lobby param) ------------------------------------

func test_route_kill_coop_with_lobby_sends_wire_packet():
	# Co-op path with a non-null lobby fans the kill over the wire so
	# remote clients learn about it. Closes the AC#3 broadcast gap:
	# without this send, remote clients never receive the kill event
	# and never apply XP for kills made on this client.
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(7)
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 1, "wire packet sent on co-op kill")
	assert_eq(lobby.sent_kills[0][0], "r3_e0", "enemy_id forwarded")
	assert_eq(lobby.sent_kills[0][1], "u1", "killer_id is the local player_id")
	assert_eq(lobby.sent_kills[0][2], 7, "xp_value is the enemy's xp_reward")

func test_route_kill_coop_null_lobby_safe():
	# Pre-handshake / test path where the lobby ref hasn't been resolved
	# yet. Local broadcast still fires; only the wire send is skipped.
	# Symmetric to the null-tracker contract on the solo branch.
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	enemy.enemy_id = "r3_e0"
	# Sixth arg (lobby) intentionally omitted — defaults to null.
	KillRewardRouter.route_kill(c, enemy, session, "u1")
	assert_eq(c.xp, 3, "local broadcast still fires without a lobby")

func test_route_kill_solo_with_lobby_does_not_send():
	# A null/inactive session takes the solo branch even if a lobby is
	# present. Solo kills never broadcast — the wire layer is co-op only.
	# Without this gate, a player who left a co-op session but kept the
	# lobby ref around would silently leak kills onto the wire.
	var c := _make_character(1)
	var enemy := _make_enemy(3)
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, null, "", null, lobby)
	assert_eq(lobby.sent_kills.size(), 0, "solo path never broadcasts")
	assert_eq(c.level, 1, "solo path applied XP locally (3 < L1->L2 threshold)")
	assert_eq(c.xp, 3, "solo path applied XP locally")

func test_route_kill_coop_inactive_session_with_lobby_does_not_send():
	# An end()'d session falls through to solo; even with a lobby the
	# kill must NOT go on the wire (post-end the broadcaster is null
	# and any wire send would be misattributed to a dead session).
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.end()
	var enemy := _make_enemy(5)
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 0, "post-end session does not broadcast")

func test_route_kill_coop_empty_enemy_id_still_calls_send():
	# The empty-enemy_id no-op gate lives inside send_kill_async itself
	# (matching how send_position_async handles its no-socket guard) —
	# the router doesn't replicate the gate. Pins that the router's
	# contract is "if co-op and lobby, fire", and the lobby decides
	# whether the packet actually goes on the wire. send_kill_async's
	# own gate handles the empty-id silently.
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := _make_enemy(3)
	# enemy_id intentionally empty (default).
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 1, "router calls send unconditionally")
	assert_eq(lobby.sent_kills[0][0], "", "empty enemy_id forwarded; gate is in send_kill_async")

func test_route_kill_coop_with_lobby_still_records_local_state():
	# The new lobby param is additive — it does NOT change the existing
	# enemy_sync.apply_death + xp_broadcaster.on_enemy_killed contract.
	# Pin all three side effects at once so a future refactor that drops
	# one (e.g. "just send, the receiver will fan out") fails loudly.
	# 4 XP keeps the kitten at L1 (L1->L2 needs 5) so the post-call xp
	# read is the raw amount routed by LocalXPRouter, not a level-up
	# remainder of zero.
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	var enemy := _make_enemy(4)
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_false(session.enemy_sync.is_alive("r3_e0"), "enemy_sync.apply_death fired")
	assert_eq(c.xp, 4, "xp_broadcaster fanned out + LocalXPRouter applied")
	assert_eq(lobby.sent_kills.size(), 1, "wire packet sent")

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

# --- GameState set_lobby kill_received bridge -------------------------------

func test_game_state_set_lobby_routes_kill_received_to_remote_applier():
	# set_lobby connects lobby.kill_received -> _on_kill_received ->
	# RemoteKillApplier.apply. Closes the inbound side of AC#3: a kill
	# packet from another client lands here, removes the enemy from the
	# local registry, and fans XP through the local broadcaster so this
	# client's LocalXPRouter applies XP to its member.real_stats.
	_snapshot_game_state()
	var lobby_state := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	# Simulate a kill packet from u2 arriving via the wire. 4 XP keeps
	# the kitten at L1 (L1->L2 needs 5) so the post-call xp read is the
	# raw amount routed by LocalXPRouter, not a level-up remainder.
	lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 4})
	assert_false(session.enemy_sync.is_alive("r3_e0"),
		"remote packet removed enemy from local registry")
	# The broadcaster fanned XP to both players; u1's LocalXPRouter
	# applied it to c.xp.
	assert_eq(c.xp, 4, "remote kill awarded XP locally via broadcaster + router")
	GameState.set_lobby(null)
	_restore_game_state()

func test_game_state_set_lobby_swap_disconnects_old_kill_handler():
	# Re-binding to a different lobby must disconnect the old lobby's
	# kill_received -> _on_kill_received connection. Otherwise a stale
	# lobby (kept alive elsewhere) could fire a phantom kill into the
	# fresh session's enemy_sync.
	_snapshot_game_state()
	var lobby_state := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var old_lobby := NakamaLobby.new()
	old_lobby.local_player_id = "u1"
	GameState.set_lobby(old_lobby)
	var new_lobby := NakamaLobby.new()
	new_lobby.local_player_id = "u1"
	GameState.set_lobby(new_lobby)
	# Firing on the old lobby must NOT reach the session anymore.
	old_lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 5})
	assert_true(session.enemy_sync.is_alive("r3_e0"),
		"old lobby disconnected — no phantom apply")
	GameState.set_lobby(null)
	_restore_game_state()

func test_game_state_set_lobby_null_does_not_crash_on_kill():
	# A solo / pre-handshake GameState (lobby == null, session == null)
	# must not crash if a stale signal somehow fires. Not a real-world
	# path (no lobby = no signal source) but pins the defensive null
	# checks in _on_kill_received.
	_snapshot_game_state()
	GameState.coop_session = null
	GameState.local_player_id = ""
	GameState.set_lobby(null)
	# Direct call to the handler (simulating a leaked signal binding).
	GameState._on_kill_received("r3_e0", "u2", 5)
	assert_true(true, "no crash on null session")
	_restore_game_state()

# --- GameState remote-kill scene-tree despawn (AC#4) -------------------------

func _spawn_enemy_in_tree(enemy_id: String) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e.data.enemy_id = enemy_id
	add_child_autofree(e)
	return e

func test_game_state_remote_kill_queues_local_enemy_for_deletion():
	# AC#4 ("no ghost enemies"): an OP_KILL packet for an enemy this
	# client never killed locally must also queue_free the visible Enemy
	# node, not just update the registry. Without this, the enemy lingers
	# on screen until the next room reload.
	_snapshot_game_state()
	var lobby_state := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby_state, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var enemy_node := _spawn_enemy_in_tree("r3_e0")
	assert_false(enemy_node.is_queued_for_deletion(),
		"sanity: enemy starts alive on screen")
	lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 4})
	assert_true(enemy_node.is_queued_for_deletion(),
		"remote kill packet queued the visible Enemy node for deletion")
	GameState.set_lobby(null)
	_restore_game_state()

func test_game_state_remote_kill_only_despawns_matching_enemy():
	# Surgical: an OP_KILL for enemy_id A must not free enemy B that's
	# also on screen. Pins that the despawn helper filters by id (not by
	# "first Enemy in group").
	_snapshot_game_state()
	var lobby_state := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var session := CoopSession.new(lobby_state, {"u1": _make_character(1), "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("r3_e0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var target := _spawn_enemy_in_tree("r3_e0")
	var bystander := _spawn_enemy_in_tree("r4_e0")
	lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 0})
	assert_true(target.is_queued_for_deletion(), "target freed")
	assert_false(bystander.is_queued_for_deletion(), "bystander untouched")
	GameState.set_lobby(null)
	_restore_game_state()

func test_game_state_remote_kill_duplicate_packet_does_not_re_despawn():
	# RemoteKillApplier.apply returns false on a duplicate packet
	# (apply_death already returned false on a previously-erased id).
	# The despawn must be gated behind that rising edge so a flaky-
	# network re-send doesn't crash trying to re-scan for a freed node.
	# We assert this indirectly: after the first OP_KILL on an unknown
	# enemy_id (apply_death returns false because never registered), the
	# enemy stays on screen.
	_snapshot_game_state()
	var lobby_state := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var session := CoopSession.new(lobby_state, {"u1": _make_character(1), "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	# Note: enemy NOT registered. apply_death returns false, despawn
	# is gated, the node stays.
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var enemy_node := _spawn_enemy_in_tree("r3_e0")
	lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 0})
	assert_false(enemy_node.is_queued_for_deletion(),
		"apply_death returned false (never registered) — despawn gated, node survives")
	GameState.set_lobby(null)
	_restore_game_state()
