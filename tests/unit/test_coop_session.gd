extends GutTest

# Test-only helpers ---------------------------------------------------------

func _make_lobby(player_specs: Array) -> LobbyState:
	# player_specs is an Array of [player_id, name, class_name_str]
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		var lp := LobbyPlayer.make(spec[0], spec[1], spec[2], false)
		ls.add_player(lp)
	return ls

func _make_character(klass: int, level: int) -> CharacterData:
	var c := CharacterData.make_new(klass, "k%d" % level)
	c.level = level
	c.max_hp = CharacterData.base_max_hp_for(klass, level)
	c.hp = c.max_hp
	c.attack = CharacterData.base_attack_for(klass, level)
	c.defense = CharacterData.base_defense_for(klass, level)
	c.speed = CharacterData.base_speed_for(klass, level)
	return c

func _make_two_room_dungeon() -> Dungeon:
	# Minimal valid dungeon: start (room 0) -> boss (room 1). Boss has an
	# explicit enemy_kind so it isn't auto-cleared by the "empty room" rule.
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

# --- Construction: parties + scaling ---------------------------------------

func test_construct_solo_party_no_scaling():
	# Solo lobby: floor == own level, scaled stats == real stats. Closes
	# the "solo session goes through the same orchestrator as co-op"
	# invariant — no special-case branch.
	var lobby := _make_lobby([["u1", "Whiskers", "Mage"]])
	var c := _make_character(CharacterData.CharacterClass.MAGE, 5)
	var session := CoopSession.new(lobby, {"u1": c})
	assert_eq(session.member_count(), 1)
	assert_eq(session.floor_level, 5, "single-member floor is own level")
	var m := session.member_for("u1")
	assert_not_null(m)
	assert_eq(m.real_stats.level, 5)
	assert_eq(m.effective_stats.level, 5, "no scaling in solo")

func test_construct_two_player_party_floors_to_lower_level():
	# Two-player lobby with mismatched levels: the higher-level player's
	# effective_stats are scaled down to the lower's; the floor player's
	# effective_stats are untouched.
	var lobby := _make_lobby([
		["u1", "Whiskers", "Mage"],
		["u2", "Shadow", "Ninja"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 10),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 3),
	}
	var session := CoopSession.new(lobby, characters)
	assert_eq(session.floor_level, 3, "floor pegs to lower level")
	var u1 := session.member_for("u1")
	var u2 := session.member_for("u2")
	assert_eq(u1.real_stats.level, 10, "real level untouched")
	assert_eq(u1.effective_stats.level, 3, "scaled to floor")
	assert_eq(u2.real_stats.level, 3)
	assert_eq(u2.effective_stats.level, 3, "floor player's effective stays at own level")

func test_construct_skips_lobby_player_with_no_character_data():
	# Defensive: a wire-payload race where the lobby roster has a player
	# but their CharacterData hasn't propagated yet shouldn't blow up.
	# That player is just skipped — they don't appear in members and
	# don't influence the floor.
	var lobby := _make_lobby([
		["u1", "Whiskers", "Mage"],
		["u2", "Ghost", "Mage"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 7),
	}
	var session := CoopSession.new(lobby, characters)
	assert_eq(session.member_count(), 1, "missing-character player skipped")
	assert_null(session.member_for("u2"), "no member row for the skipped id")
	assert_eq(session.floor_level, 7, "floor ignores missing player")

func test_construct_null_lobby_safe():
	# Allow a default-constructed session for tests / future paths where
	# the lobby isn't ready. No members, no crash.
	var session := CoopSession.new()
	assert_eq(session.member_count(), 0)
	assert_eq(session.floor_level, 1, "safe default floor")
	assert_null(session.lobby)

func test_construct_empty_lobby_yields_empty_party():
	var lobby := LobbyState.new("ABCDE")
	var session := CoopSession.new(lobby, {})
	assert_eq(session.member_count(), 0)
	assert_eq(session.floor_level, 1, "empty party falls through to safe floor")

func test_construct_skips_player_with_empty_id():
	# A LobbyPlayer with an empty player_id can't be looked up by id and
	# can't be registered with XPBroadcaster (which rejects empty ids).
	# Skip it at construction so the orchestrator never has to surface
	# half-registered members.
	var lobby := LobbyState.new("ABCDE")
	lobby.add_player(LobbyPlayer.make("u1", "A", "Mage"))
	# Bypass add_player's validation to inject a malformed entry — same
	# shape a corrupt wire payload could produce.
	var bad := LobbyPlayer.new()
	bad.player_id = ""
	lobby.players.append(bad)
	var characters := {"u1": _make_character(CharacterData.CharacterClass.MAGE, 4)}
	var session := CoopSession.new(lobby, characters)
	assert_eq(session.member_count(), 1, "empty-id member skipped")

# --- start() ---------------------------------------------------------------

func test_start_builds_managers_and_emits_signal():
	var lobby := _make_lobby([["u1", "Whiskers", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	var emitted := [false]
	session.session_started.connect(func(): emitted[0] = true)

	assert_null(session.xp_broadcaster, "manager is null pre-start")
	assert_true(session.start(_make_two_room_dungeon()), "start returns true")
	assert_true(session.is_active())
	assert_true(emitted[0], "session_started fired exactly once")

	# All five per-run managers are non-null.
	assert_not_null(session.xp_broadcaster)
	assert_not_null(session.xp_summary)
	assert_not_null(session.network_sync)
	assert_not_null(session.enemy_sync)
	assert_not_null(session.run_controller)

func test_start_registers_all_party_ids_with_broadcaster():
	# A kill-by-anyone XP broadcast must fan out to every party id; the
	# session is the wire-up layer that registers them at run start so
	# the future XP-routing caller doesn't have to.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
		["u3", "C", "Thief"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 3),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 5),
		"u3": _make_character(CharacterData.CharacterClass.THIEF, 4),
	}
	var session := CoopSession.new(lobby, characters)
	session.start(_make_two_room_dungeon())
	assert_eq(session.xp_broadcaster.player_count(), 3)
	assert_true(session.xp_broadcaster.has_player("u1"))
	assert_true(session.xp_broadcaster.has_player("u2"))
	assert_true(session.xp_broadcaster.has_player("u3"))

func test_start_xp_summary_subscribes_to_broadcaster():
	# The summary must accumulate broadcasts that fire after start().
	# Pins the wire-up between XPBroadcaster and RunXPSummary.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	session.xp_broadcaster.on_enemy_killed(15)
	assert_eq(session.xp_summary.total_for("u1"), 15)
	assert_eq(session.xp_summary.grand_total(), 15)

func test_start_returns_false_on_null_dungeon():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_false(session.start(null))
	assert_false(session.is_active())
	# Rollback: managers should not be left half-built.
	assert_null(session.xp_broadcaster)
	assert_null(session.run_controller)

func test_start_returns_false_on_empty_party():
	# An empty party is a likely mis-construction (lobby never populated /
	# all character data missing). Reject the start so the caller surfaces
	# the error rather than silently running with a no-op broadcaster.
	var session := CoopSession.new()
	assert_false(session.start(_make_two_room_dungeon()))
	assert_false(session.is_active())

func test_start_idempotent_when_already_active():
	# A second start() call without an end() is a no-op (returns false).
	# Locks against a UI bug where a "Start Match" button could be tapped
	# twice and rebuild the managers, dropping the first run's state.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_true(session.start(_make_two_room_dungeon()))
	var first_broadcaster = session.xp_broadcaster
	assert_false(session.start(_make_two_room_dungeon()), "second start rejected")
	assert_eq(session.xp_broadcaster, first_broadcaster, "managers preserved")

func test_start_rolls_back_on_dungeon_controller_rejection():
	# A dungeon with start_id < 0 is rejected by DungeonRunController.start.
	# The session must roll back the managers it constructed before that
	# point so a rejected start doesn't leave dangling references.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	var bad := Dungeon.new()
	# start_id stays at -1 (default); controller will reject this.
	assert_false(session.start(bad))
	assert_false(session.is_active())
	assert_null(session.xp_broadcaster)
	assert_null(session.xp_summary)
	assert_null(session.run_controller)

# --- dungeon_completed wiring ----------------------------------------------

func test_dungeon_completed_advances_meta_and_flips_completion_flag():
	# Boss-room cleared edge fires DungeonRunCompletion.complete via the
	# session's wire-up. The meta tracker advances and the session's
	# `was_dungeon_completed()` flips so the summary screen can render
	# the "Victory!" header without reaching through to run_controller.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var tracker := MetaProgressionTracker.new()
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		tracker,
	)
	var completions: Array = []
	session.run_completed.connect(func(): completions.append(true))
	session.start(_make_two_room_dungeon())
	assert_false(session.was_dungeon_completed(), "false pre-clear")
	session.run_controller.mark_room_cleared(1)
	assert_eq(tracker.dungeons_completed, 1, "meta tracker advanced")
	assert_true(session.was_dungeon_completed(), "completion flag flipped")
	assert_eq(completions.size(), 1, "session re-emitted run_completed exactly once")

func test_dungeon_completed_safe_when_tracker_null():
	# A test-only / fresh-install path with no GameState attached must
	# still complete cleanly. DungeonRunCompletion is null-safe; the
	# session's wire-up shouldn't add a non-null requirement.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	session.run_controller.mark_room_cleared(1)
	assert_true(session.was_dungeon_completed(),
		"completion flag flips even with a null tracker")

# --- end() -----------------------------------------------------------------

func test_end_drops_managers_and_unscales_members():
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 10),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 3),
	}
	var session := CoopSession.new(lobby, characters)
	session.start(_make_two_room_dungeon())
	# Pre-end: u1 is scaled down to floor 3.
	assert_eq(session.member_for("u1").effective_stats.level, 3)

	var ended := [false]
	session.session_ended.connect(func(): ended[0] = true)
	assert_true(session.end())
	assert_true(ended[0], "session_ended fired")
	assert_false(session.is_active())
	# Managers dropped.
	assert_null(session.xp_broadcaster)
	assert_null(session.xp_summary)
	assert_null(session.network_sync)
	assert_null(session.enemy_sync)
	assert_null(session.run_controller)
	# Scaling removed: effective == real for every member.
	assert_eq(session.member_for("u1").effective_stats.level, 10)
	assert_eq(session.member_for("u2").effective_stats.level, 3)

func test_end_idempotent_when_not_active():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_false(session.end(), "end before start returns false")
	# After a real end(), a second call is also false.
	session.start(_make_two_room_dungeon())
	assert_true(session.end())
	assert_false(session.end(), "second end returns false")

func test_end_preserves_lobby_and_members_for_next_run():
	# Multi-run match: same lobby, same party, fresh dungeon. end() must
	# preserve the roster so start() can be called again without re-
	# constructing the whole session.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 4)})
	assert_true(session.start(_make_two_room_dungeon()))
	assert_true(session.end())
	# Lobby + members + floor preserved.
	assert_not_null(session.lobby)
	assert_eq(session.member_count(), 1)
	assert_eq(session.floor_level, 4)
	# Re-start against a fresh dungeon works.
	assert_true(session.start(_make_two_room_dungeon()))
	assert_true(session.is_active())

# --- member_for ------------------------------------------------------------

func test_member_for_unknown_id_returns_null():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_null(session.member_for("ghost"))
	assert_null(session.member_for(""))

func test_player_ids_preserve_lobby_join_order():
	# Summary screen renders rows in join order. Pin that the orchestrator
	# preserves it (vs. dictionary-iteration order) so the UI doesn't
	# shuffle rows between runs.
	var lobby := _make_lobby([
		["alice", "A", "Mage"],
		["bob", "B", "Ninja"],
		["carol", "C", "Thief"],
	])
	var characters := {
		"alice": _make_character(CharacterData.CharacterClass.MAGE, 3),
		"bob": _make_character(CharacterData.CharacterClass.NINJA, 3),
		"carol": _make_character(CharacterData.CharacterClass.THIEF, 3),
	}
	var session := CoopSession.new(lobby, characters)
	assert_eq(session.player_ids, ["alice", "bob", "carol"])

# --- end-to-end ------------------------------------------------------------

func test_end_to_end_three_player_run_summary():
	# Full-shape session: three players join, party scales to lowest
	# level, run starts, three kills broadcast XP through the session,
	# boss kill advances meta, end() unscales. Summary tally has every
	# player's per-run total.
	var lobby := _make_lobby([
		["alice", "A", "Mage"],
		["bob", "B", "Ninja"],
		["carol", "C", "Thief"],
	])
	var characters := {
		"alice": _make_character(CharacterData.CharacterClass.MAGE, 8),
		"bob": _make_character(CharacterData.CharacterClass.NINJA, 3),
		"carol": _make_character(CharacterData.CharacterClass.THIEF, 5),
	}
	var tracker := MetaProgressionTracker.new()
	var session := CoopSession.new(lobby, characters, tracker)
	assert_eq(session.floor_level, 3, "scaled to lowest")
	session.start(_make_two_room_dungeon())

	# Three kills route through the broadcaster.
	session.xp_broadcaster.on_enemy_killed(5)   # rat
	session.xp_broadcaster.on_enemy_killed(8)   # wraith
	session.xp_broadcaster.on_enemy_killed(20)  # boss

	# Each player accumulated all three rewards (kill-by-anyone).
	assert_eq(session.xp_summary.total_for("alice"), 33)
	assert_eq(session.xp_summary.total_for("bob"), 33)
	assert_eq(session.xp_summary.total_for("carol"), 33)
	assert_eq(session.xp_summary.grand_total(), 99)

	# Boss-room cleared edge advances the meta tracker.
	session.run_controller.mark_room_cleared(1)
	assert_eq(tracker.dungeons_completed, 1)
	assert_true(session.was_dungeon_completed())

	# end() unscales every member.
	session.end()
	assert_eq(session.member_for("alice").effective_stats.level, 8, "unscaled")
	assert_eq(session.member_for("bob").effective_stats.level, 3)
	assert_eq(session.member_for("carol").effective_stats.level, 5, "unscaled")

# --- CoopXPSubscriber wiring --------------------------------------------------

func test_start_builds_xp_router_when_local_player_in_party():
	# A session constructed with a local_player_id matching one of the
	# party builds a CoopXPSubscriber on start so the kill-by-anyone
	# broadcast lands on this client's PartyMember.real_stats.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 1),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 1),
	}
	var session := CoopSession.new(lobby, characters, null, "u1")
	assert_null(session.xp_subscriber, "router is null pre-start")
	session.start(_make_two_room_dungeon())
	assert_not_null(session.xp_subscriber, "router built on start")
	assert_true(session.xp_subscriber.is_bound())
	assert_eq(session.xp_subscriber.local_player_id, "u1")
	# The router is bound to *this client's* member, not a remote one.
	assert_eq(session.xp_subscriber.local_member, session.member_for("u1"))

func test_start_skips_xp_router_when_local_player_id_empty():
	# Default-constructed (test / pre-handshake) session has no local
	# player_id. The router would have nothing to filter on, so start()
	# skips building it. xp_summary still tallies broadcasts; just no
	# stats land anywhere.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	assert_null(session.xp_subscriber, "router skipped without local id")

func test_start_skips_xp_router_when_local_id_not_in_party():
	# Defensive: a session constructed with a local_player_id not present
	# in the lobby (e.g. wire-payload race, save-restore mismatch) should
	# not crash. Skip the router rather than building one with a null
	# member that would silently drop every event.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var characters := {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}
	var session := CoopSession.new(lobby, characters, null, "ghost")
	session.start(_make_two_room_dungeon())
	assert_null(session.xp_subscriber, "unknown local id => no router")

func test_xp_broadcast_routes_to_local_member_real_stats_via_session():
	# End-to-end through the session: a kill broadcast routes XP to the
	# local PartyMember.real_stats via the wired-up CoopXPSubscriber. Pins
	# that the orchestrator wiring (broadcaster + router) actually
	# lands XP on the local character without any extra plumbing.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 1),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 1),
	}
	var session := CoopSession.new(lobby, characters, null, "u1")
	session.start(_make_two_room_dungeon())
	var u1_pre_xp := session.member_for("u1").real_stats.xp
	var u2_pre_xp := session.member_for("u2").real_stats.xp
	session.xp_broadcaster.on_enemy_killed(3, "u2")  # u2 got the killing blow
	# Local client (u1) routes its emission to its own real_stats.
	assert_eq(session.member_for("u1").real_stats.xp, u1_pre_xp + 3,
		"local member real_stats received XP")
	# Remote member (u2) is *not* mutated on this client — that's
	# handled by u2's own client. The local router filters by pid so
	# u2's emission doesn't bleed onto u2's stats from this client.
	assert_eq(session.member_for("u2").real_stats.xp, u2_pre_xp,
		"remote member real_stats untouched on local client")

func test_xp_broadcast_routes_to_real_stats_not_effective_when_scaled():
	# AC #18#3: a level-10 player scaled down to floor 3 still earns
	# XP toward their actual level 10 (not the scaled level 3). Pins
	# the use_real_level=true rule at the session+router seam.
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var characters := {
		"u1": _make_character(CharacterData.CharacterClass.MAGE, 10),
		"u2": _make_character(CharacterData.CharacterClass.NINJA, 3),
	}
	var session := CoopSession.new(lobby, characters, null, "u1")
	session.start(_make_two_room_dungeon())
	# Pre-kill: u1 is scaled to floor 3, but real_stats stays at 10.
	assert_eq(session.member_for("u1").effective_stats.level, 3)
	assert_eq(session.member_for("u1").real_stats.level, 10)
	var pre_real_xp := session.member_for("u1").real_stats.xp
	var pre_effective_xp := session.member_for("u1").effective_stats.xp
	session.xp_broadcaster.on_enemy_killed(3)
	assert_eq(session.member_for("u1").real_stats.xp, pre_real_xp + 3,
		"XP advanced real_stats")
	assert_eq(session.member_for("u1").effective_stats.xp, pre_effective_xp,
		"effective_stats untouched (scaled view doesn't progress)")

func test_end_drops_xp_router():
	# Per-run lifecycle: end() must drop the router so a stale subscriber
	# from the previous run can't keep mutating the local member's stats
	# after the session is torn down.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		null, "u1")
	session.start(_make_two_room_dungeon())
	var bc_before_end := session.xp_broadcaster
	var member := session.member_for("u1")
	assert_not_null(session.xp_subscriber)
	session.end()
	assert_null(session.xp_subscriber, "router dropped on end")
	# A late broadcast on the (still-held) old broadcaster should not
	# mutate the member's stats — router unbound means the subscriber
	# is gone.
	var pre_xp := member.real_stats.xp
	bc_before_end.on_enemy_killed(99)
	assert_eq(member.real_stats.xp, pre_xp, "post-end broadcast ignored")

func test_xp_router_rebuilds_on_next_run_after_end():
	# Multi-run match: end() drops the router, the next start() rebuilds
	# it bound to the new run's broadcaster + (preserved) member.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		null, "u1")
	session.start(_make_two_room_dungeon())
	session.end()
	session.start(_make_two_room_dungeon())
	assert_not_null(session.xp_subscriber)
	# New router bound to the new broadcaster.
	session.xp_broadcaster.on_enemy_killed(3)
	assert_eq(session.member_for("u1").real_stats.xp, 3,
		"second run's broadcasts route through fresh router")

# --- dungeon_seed_sync borrowed reference (#17 AC#1) -----------------------

func test_dungeon_seed_sync_defaults_null():
	# Solo / pre-handshake / test path: no seed sync handed in => null. The
	# main_scene consumer null-checks before reading is_agreed() so this falls
	# through to DungeonGenerator's randomize sentinel.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_null(session.dungeon_seed_sync,
		"default null when no seed sync passed")

func test_dungeon_seed_sync_stored_from_constructor():
	# The lobby's start handler hands the same DungeonSeedSync instance to
	# every client's CoopSession at match start so main_scene reads the
	# agreed seed from session.dungeon_seed_sync.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var seed_sync := DungeonSeedSync.new()
	seed_sync.host_mint(4242)
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		null, "u1", seed_sync,
	)
	assert_eq(session.dungeon_seed_sync, seed_sync,
		"session holds the borrowed seed sync reference")
	assert_true(session.dungeon_seed_sync.is_agreed())
	assert_eq(session.dungeon_seed_sync.current_seed(), 4242,
		"agreed seed visible through session field")

func test_dungeon_seed_sync_survives_end_start_cycle():
	# Multi-run lobby: end() drops per-run managers but the seed sync is
	# borrowed (lobby-owned), so it must persist across end()/start() pairs
	# unchanged. The lobby is responsible for reset() between matches —
	# CoopSession just holds the reference.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var seed_sync := DungeonSeedSync.new()
	seed_sync.host_mint(1234)
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		null, "u1", seed_sync,
	)
	session.start(_make_two_room_dungeon())
	session.end()
	assert_eq(session.dungeon_seed_sync, seed_sync,
		"end() does not drop the borrowed seed sync ref")
	assert_true(session.dungeon_seed_sync.is_agreed(),
		"borrowed sync state preserved across end()")

# --- position_broadcast_gate lifecycle (#35) -------------------------------

func test_position_broadcast_gate_null_pre_start():
	# Solo / pre-handshake path: the gate doesn't exist until a run starts.
	# Player.gd's _maybe_broadcast_position null-checks this so solo play
	# leaves the wire untouched.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	assert_null(session.position_broadcast_gate, "gate is null pre-start")

func test_start_constructs_position_broadcast_gate():
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	assert_not_null(session.position_broadcast_gate, "gate built on start")
	assert_false(session.position_broadcast_gate.has_broadcast(),
		"fresh gate has no prior broadcast")

func test_end_drops_position_broadcast_gate():
	# Per-run lifecycle parity with the other managers — end() must drop
	# the gate so a stale baseline from the previous run can't suppress
	# the first broadcast of the next run.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	# Mark a broadcast so a leaked gate would be observably different
	# from a fresh one.
	session.position_broadcast_gate.try_broadcast(0.0, Vector2(10, 20))
	session.end()
	assert_null(session.position_broadcast_gate, "gate dropped on end")

func test_position_broadcast_gate_rebuilds_on_next_run():
	# Multi-run match: each run gets a fresh gate so the first packet of
	# the new run lands at the new spawn point immediately rather than
	# being suppressed by the previous run's last-broadcast baseline.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	var first_gate = session.position_broadcast_gate
	session.end()
	session.start(_make_two_room_dungeon())
	assert_not_null(session.position_broadcast_gate)
	assert_ne(session.position_broadcast_gate, first_gate,
		"second run gets a fresh gate instance")

# --- finalize_run_summary --------------------------------------------------
# Closes AC#5 ("End-of-run screen shows XP earned by each player") on the
# data side. Before finalize_run_summary, main_scene._on_dungeon_completed
# reloaded the scene without snapshotting the live xp_summary anywhere —
# the future summary screen had nothing to read after the per-run managers
# dropped. After finalize_run_summary, the rows + header are frozen on the
# session and survive the scene reload (session is a GameState autoload
# field, not a scene-tree node) and a subsequent end() call.

func test_finalize_run_summary_captures_snapshot_and_emits_signal():
	var lobby := _make_lobby([
		["alice", "Whiskers", "Mage"],
		["bob", "Shadow", "Ninja"],
	])
	var characters := {
		"alice": _make_character(CharacterData.CharacterClass.MAGE, 5),
		"bob": _make_character(CharacterData.CharacterClass.NINJA, 5),
	}
	var session := CoopSession.new(lobby, characters, null, "alice")
	session.start(_make_two_room_dungeon())

	# Two kills fan XP to every member via the broadcaster.
	session.xp_broadcaster.on_enemy_killed(7)
	session.xp_broadcaster.on_enemy_killed(13)

	# Pre-finalize: header / rows are empty, dungeon_completed false.
	assert_false(session.was_dungeon_completed())
	assert_eq(session.last_run_summary_header, {})
	assert_eq(session.last_run_summary_rows, [])

	var emit_count := [0]
	session.run_completed.connect(func(): emit_count[0] += 1)

	assert_true(session.finalize_run_summary(),
		"rising-edge finalize returns true")

	# Snapshot captured: header + rows reflect the live tally.
	assert_true(session.was_dungeon_completed())
	assert_eq(emit_count[0], 1, "run_completed emitted exactly once")
	assert_eq(session.last_run_summary_rows.size(), 2,
		"one row per party member")
	assert_eq(session.last_run_summary_header.get("party_size"), 2)
	assert_eq(session.last_run_summary_header.get("grand_total_xp"), 40,
		"sum of (7+13) * 2 members")
	assert_true(session.last_run_summary_header.get("dungeon_completed"),
		"header reflects victory state")
	assert_eq(session.last_run_summary_header.get("local_player_id"), "alice",
		"header carries the local player id")

func test_finalize_run_summary_idempotent_within_run():
	# A second call (e.g. duplicate handler invocation) must not double-emit
	# run_completed nor overwrite the captured snapshot.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	session.xp_broadcaster.on_enemy_killed(10)

	var emit_count := [0]
	session.run_completed.connect(func(): emit_count[0] += 1)

	assert_true(session.finalize_run_summary(), "first call rising edge")
	var first_header: Dictionary = session.last_run_summary_header
	var first_rows: Array = session.last_run_summary_rows

	assert_false(session.finalize_run_summary(),
		"second call within the same run returns false")
	assert_eq(emit_count[0], 1, "no double-emit of run_completed")
	assert_same(session.last_run_summary_header, first_header,
		"snapshot reference unchanged on no-op")
	assert_same(session.last_run_summary_rows, first_rows,
		"rows reference unchanged on no-op")

func test_finalize_run_summary_snapshot_survives_end():
	# AC#5 contract: the summary screen reads the snapshot AFTER end()
	# drops the live xp_summary. The captured fields must outlive the
	# per-run managers.
	var lobby := _make_lobby([["u1", "Whiskers", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 4)}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.xp_broadcaster.on_enemy_killed(25)
	session.finalize_run_summary()

	assert_not_null(session.xp_summary, "summary live pre-end")
	session.end()
	assert_null(session.xp_summary, "live tally dropped on end")

	# Snapshot still readable post-end.
	assert_eq(session.last_run_summary_rows.size(), 1)
	assert_eq(session.last_run_summary_header.get("grand_total_xp"), 25)
	assert_true(session.was_dungeon_completed(),
		"completion flag survives end (sticky)")

func test_finalize_run_summary_safe_pre_start():
	# Default-constructed / pre-start session: no xp_summary, no lobby.
	# finalize must not crash; it just freezes empty rows and a default
	# header so a UI flow that defensively calls finalize before start
	# (shouldn't happen, but guard anyway) doesn't NPE.
	var session := CoopSession.new()
	assert_true(session.finalize_run_summary(),
		"finalize on a fresh session still rising-edges")
	assert_eq(session.last_run_summary_rows, [],
		"no party => empty rows")
	assert_eq(session.last_run_summary_header.get("party_size"), 0)
	assert_true(session.last_run_summary_header.get("dungeon_completed"),
		"finalize sets the flag even on a fresh session")

func test_legacy_run_controller_completion_path_populates_snapshot():
	# Back-compat: tests that drive session.run_controller directly (the
	# legacy path) must still bump the meta tracker AND populate the
	# snapshot via the same finalize_run_summary code path. Refactoring
	# session._on_dungeon_completed to delegate to finalize_run_summary
	# means both entry points produce the same post-completion state.
	var lobby := _make_lobby([
		["alice", "Whiskers", "Mage"],
		["bob", "Shadow", "Ninja"],
	])
	var characters := {
		"alice": _make_character(CharacterData.CharacterClass.MAGE, 5),
		"bob": _make_character(CharacterData.CharacterClass.NINJA, 5),
	}
	var tracker := MetaProgressionTracker.new()
	var session := CoopSession.new(lobby, characters, tracker, "alice")
	session.start(_make_two_room_dungeon())
	session.xp_broadcaster.on_enemy_killed(11)

	# Drive session.run_controller's boss-cleared edge (the legacy / test
	# path that doesn't go through main_scene).
	session.run_controller.mark_room_cleared(1)

	assert_eq(tracker.dungeons_completed, 1, "legacy path bumps meta tracker")
	assert_true(session.was_dungeon_completed())
	assert_eq(session.last_run_summary_rows.size(), 2,
		"legacy path also populates snapshot")
	assert_eq(session.last_run_summary_header.get("grand_total_xp"), 22,
		"11 XP * 2 members")

# --- is_routing_ready() predicate -------------------------------------------

func test_is_routing_ready_returns_false_when_not_active():
	# Constructed but not started — must return false so routers take the
	# solo branch rather than trying to use null managers.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}, null, "u1")
	assert_false(session.is_active())
	assert_false(session.is_routing_ready())

func test_is_routing_ready_returns_false_with_empty_local_player_id():
	# A session where local_player_id was never set (pre-handshake or
	# default-constructed) must return false — no local id, no co-op routing.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}, null, "")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_active())
	assert_false(session.is_routing_ready())

func test_is_routing_ready_returns_true_for_active_session_with_local_member():
	# The canonical "co-op is live and this client is in the party" case.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_routing_ready())

func test_is_routing_ready_returns_false_after_end():
	# end() deactivates the run — routers must fall back to solo path.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_routing_ready())
	session.end()
	assert_false(session.is_routing_ready())

func test_is_routing_ready_returns_false_when_local_player_not_in_party():
	# local_player_id is set but the player isn't in the party roster
	# (e.g. a wire-race where local_id arrived before CharacterData).
	# Must return false — can't route to a member that doesn't exist.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)}, null, "u2")
	session.start(_make_two_room_dungeon())
	assert_true(session.is_active())
	assert_null(session.member_for("u2"))
	assert_false(session.is_routing_ready())
