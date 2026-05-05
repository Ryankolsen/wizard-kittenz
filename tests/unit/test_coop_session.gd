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

func test_dungeon_completed_grants_tokens_and_advances_meta():
	# Boss-room cleared edge fires DungeonRunCompletion.complete via the
	# session's wire-up. Both side effects (meta tracker + token grant)
	# land. The session re-emits the grant count via its own signal so
	# the future "+N tokens" toast doesn't need to know about the
	# DungeonRunCompletion helper.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var tracker := MetaProgressionTracker.new()
	var inventory := TokenInventory.new()
	var session := CoopSession.new(
		lobby,
		{"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)},
		tracker,
		inventory,
	)
	var grants: Array = []
	session.dungeon_completed_grant.connect(func(n): grants.append(n))
	session.start(_make_two_room_dungeon())
	# Mark the boss room cleared — DungeonRunController fires the
	# dungeon_completed signal which the session bridges to
	# DungeonRunCompletion.complete.
	session.run_controller.mark_room_cleared(1)
	assert_eq(tracker.dungeons_completed, 1, "meta tracker advanced")
	assert_eq(inventory.count, TokenGrantRules.tokens_for_dungeon_complete(),
		"inventory granted the dungeon-complete amount")
	assert_eq(grants.size(), 1, "session emitted exactly one grant signal")
	assert_eq(grants[0], TokenGrantRules.tokens_for_dungeon_complete())
	assert_eq(session.last_completion_grant(), TokenGrantRules.tokens_for_dungeon_complete())

func test_dungeon_completed_safe_when_tracker_and_inventory_null():
	# A test-only / fresh-install path with no GameState attached must
	# still complete cleanly. DungeonRunCompletion is null-safe; the
	# session's wire-up shouldn't add a non-null requirement.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": _make_character(CharacterData.CharacterClass.MAGE, 1)})
	session.start(_make_two_room_dungeon())
	# Should not crash — both args null, complete returns 0.
	session.run_controller.mark_room_cleared(1)
	assert_eq(session.last_completion_grant(), 0)

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
	# boss kill grants tokens, end() unscales. Summary tally has every
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
	var inventory := TokenInventory.new()
	var session := CoopSession.new(lobby, characters, tracker, inventory)
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

	# Boss-room cleared edge fires the dungeon_completed grant.
	session.run_controller.mark_room_cleared(1)
	assert_eq(tracker.dungeons_completed, 1)
	assert_eq(inventory.count, TokenGrantRules.tokens_for_dungeon_complete())

	# end() unscales every member.
	session.end()
	assert_eq(session.member_for("alice").effective_stats.level, 8, "unscaled")
	assert_eq(session.member_for("bob").effective_stats.level, 3)
	assert_eq(session.member_for("carol").effective_stats.level, 5, "unscaled")
