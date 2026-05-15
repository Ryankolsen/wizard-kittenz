extends GutTest

const TMP_PATH := "user://test_save_sync.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# --- SaveManager round-trip -------------------------------------------------

func test_save_manager_writes_and_loads_with_identical_level_and_xp():
	# Issue scenario 1: Core wiring — SaveManager.save writes to disk
	# and SaveManager.load returns data with identical level and xp.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Mittens")
	c.level = 4
	c.xp = 7
	var err := SaveManager.save(c, TMP_PATH)
	assert_eq(err, OK, "save returns OK")
	assert_true(FileAccess.file_exists(TMP_PATH), "file written")
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.level, 4, "level round-trips")
	assert_eq(loaded.xp, 7, "xp round-trips")

# --- OfflineProgressMerger.resolve ------------------------------------------

func test_resolve_local_wins_when_local_level_higher():
	# Issue scenario 2: local higher level wins.
	var local := KittenSaveData.new()
	local.level = 7
	local.xp = 3
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 2
	var winner := OfflineProgressMerger.resolve(local, server)
	assert_eq(winner, local, "local wins when level is strictly higher")

func test_resolve_server_wins_when_server_level_higher():
	# Issue scenario 3: server higher level wins.
	var local := KittenSaveData.new()
	local.level = 4
	var server := KittenSaveData.new()
	server.level = 8
	var winner := OfflineProgressMerger.resolve(local, server)
	assert_eq(winner, server, "server wins when level is strictly higher")

func test_resolve_local_wins_on_tie():
	# Tie-breaker rule: local wins because local is "what the player
	# sees right now." Avoids the worst UX bug — "I just played and my
	# session vanished after sign-in."
	var local := KittenSaveData.new()
	local.level = 6
	local.xp = 9
	var server := KittenSaveData.new()
	server.level = 6
	server.xp = 1
	var winner := OfflineProgressMerger.resolve(local, server)
	assert_eq(winner, local, "tie -> local")

func test_resolve_handles_null_inputs():
	var s := KittenSaveData.new()
	s.level = 3
	assert_eq(OfflineProgressMerger.resolve(null, s), s, "null local -> server")
	assert_eq(OfflineProgressMerger.resolve(s, null), s, "null server -> local")
	assert_null(OfflineProgressMerger.resolve(null, null))

# --- OfflineProgressMerger.merge_xp -----------------------------------------

func test_merge_xp_adds_offline_xp_to_server_at_equal_level():
	# Issue scenario 4: when local.level == server.level, merge_xp
	# adds local.offline_xp_earned to server.xp.
	var local := KittenSaveData.new()
	local.level = 5
	local.xp = 12
	local.offline_xp_earned = 8
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 4
	var merged := OfflineProgressMerger.merge_xp(local, server)
	assert_eq(merged.xp, 12, "server.xp + local.offline_xp_earned (4 + 8 = 12)")
	assert_eq(merged.level, 5, "level unchanged")
	assert_eq(server.xp, 4, "input server is not mutated")
	assert_eq(local.xp, 12, "input local is not mutated")

func test_merge_xp_is_noop_when_levels_differ():
	# When levels differ, resolve() already picked a winner; the offline
	# XP delta is already baked into local.xp / local.level. Re-applying
	# it would double-count.
	var local := KittenSaveData.new()
	local.level = 6
	local.offline_xp_earned = 20
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 3
	var merged := OfflineProgressMerger.merge_xp(local, server)
	assert_eq(merged.xp, 3, "differing levels -> server.xp unchanged")
	assert_eq(merged.level, 5)

func test_merge_xp_is_noop_when_offline_xp_is_zero_or_negative():
	var local := KittenSaveData.new()
	local.level = 5
	local.offline_xp_earned = 0
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 7
	assert_eq(OfflineProgressMerger.merge_xp(local, server).xp, 7, "zero -> noop")
	local.offline_xp_earned = -3
	assert_eq(OfflineProgressMerger.merge_xp(local, server).xp, 7, "negative -> noop")

func test_merge_xp_returns_clone_not_server_reference():
	# Mutating the merged result must not stealth-mutate the server input.
	var local := KittenSaveData.new()
	local.level = 5
	local.offline_xp_earned = 5
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 10
	var merged := OfflineProgressMerger.merge_xp(local, server)
	merged.xp = 999
	assert_eq(server.xp, 10, "server input unchanged after merged result mutation")

func test_merge_xp_handles_null_local():
	var server := KittenSaveData.new()
	server.level = 3
	server.xp = 5
	var merged := OfflineProgressMerger.merge_xp(null, server)
	assert_eq(merged.xp, 5, "null local -> clone of server")
	assert_eq(merged.level, 3)

func test_merge_xp_handles_null_server():
	var local := KittenSaveData.new()
	assert_null(OfflineProgressMerger.merge_xp(local, null))

# --- KittenSaveData.offline_xp_earned round-trip ----------------------------

func test_offline_xp_earned_round_trips_through_dict():
	var s := KittenSaveData.new()
	s.offline_xp_earned = 42
	var d := s.to_dict()
	var restored := KittenSaveData.from_dict(d)
	assert_eq(restored.offline_xp_earned, 42)

func test_offline_xp_earned_defaults_to_zero_for_legacy_saves():
	# A save written before the field existed has no "offline_xp_earned"
	# key. from_dict must default to 0 so the round-trip is non-lossy.
	var legacy := {"level": 3, "xp": 5}
	var restored := KittenSaveData.from_dict(legacy)
	assert_eq(restored.offline_xp_earned, 0)

# --- OfflineXPTracker -------------------------------------------------------

func test_offline_xp_tracker_starts_empty():
	# Fresh-install / no-save default: pending counter is zero so
	# OfflineProgressMerger.merge_xp on first sync is a clean no-op.
	var t := OfflineXPTracker.new()
	assert_eq(t.pending_xp, 0)
	assert_true(t.is_empty())

func test_offline_xp_tracker_record_accumulates():
	var t := OfflineXPTracker.new()
	assert_eq(t.record(5), 5, "record returns new total")
	assert_eq(t.pending_xp, 5)
	assert_eq(t.record(7), 12, "second record sums in")
	assert_false(t.is_empty())

func test_offline_xp_tracker_record_rejects_non_positive():
	# Defense-in-depth: a future debuff path that hands a 0 / negative
	# award must not decrement the counter. The merge logic assumes
	# pending_xp is the amount the server is missing — never a refund.
	var t := OfflineXPTracker.new()
	t.record(5)
	assert_eq(t.record(0), 5, "zero amount no-op")
	assert_eq(t.record(-3), 5, "negative amount no-op")
	assert_eq(t.pending_xp, 5)

func test_offline_xp_tracker_clear_resets_and_returns_previous():
	# clear() returns the previous total so the sync orchestrator can
	# log "+N XP merged" without re-reading pending_xp before the call.
	var t := OfflineXPTracker.new()
	t.record(13)
	assert_eq(t.clear(), 13, "clear returns previous total")
	assert_eq(t.pending_xp, 0)
	assert_true(t.is_empty())

func test_offline_xp_tracker_clear_idempotent():
	var t := OfflineXPTracker.new()
	assert_eq(t.clear(), 0, "clear on empty returns 0")
	t.record(4)
	t.clear()
	assert_eq(t.clear(), 0, "second clear returns 0")
	assert_eq(t.pending_xp, 0)

# --- KittenSaveData round-trip with tracker ---------------------------------

func test_kitten_save_data_from_character_captures_tracker_pending_xp():
	# The save layer captures the tracker's pending_xp into the save's
	# offline_xp_earned field so OfflineProgressMerger.merge_xp can fold
	# it into the server record on reconnect.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Whiskers")
	var t := OfflineXPTracker.new()
	t.record(17)
	var s := KittenSaveData.from_character(c, null, null, t)
	assert_eq(s.offline_xp_earned, 17)

func test_kitten_save_data_from_character_null_tracker_keeps_default():
	# Test paths / call sites that don't pass a tracker keep the field
	# at its default (0). Locks the back-compat contract that the new
	# trailing param is opt-in.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var s := KittenSaveData.from_character(c, null, null, null)
	assert_eq(s.offline_xp_earned, 0)

func test_kitten_save_data_to_offline_xp_tracker_hydrates_pending():
	# Round-trip: a save with offline_xp_earned=N produces a tracker
	# with pending_xp=N. Lets GameState.offline_xp_tracker pick up where
	# the previous session left off.
	var s := KittenSaveData.new()
	s.offline_xp_earned = 23
	var t := s.to_offline_xp_tracker()
	assert_eq(t.pending_xp, 23)

func test_kitten_save_data_to_offline_xp_tracker_zero_default():
	# Legacy / fresh save: no offline activity hydrates to an empty tracker.
	var s := KittenSaveData.new()
	var t := s.to_offline_xp_tracker()
	assert_eq(t.pending_xp, 0)
	assert_true(t.is_empty())

# --- Token economy removal (#30) — legacy save compatibility ----------------

func test_legacy_save_with_revive_tokens_key_loads_cleanly():
	# Saves predating the token-economy removal carry a `revive_tokens` int.
	# from_dict must silently drop the key — loading must not crash, and
	# no token state should leak onto the loaded save.
	var legacy := {
		"character_name": "Old",
		"character_class": int(CharacterData.CharacterClass.WIZARD_KITTEN),
		"level": 1, "xp": 0,
		"hp": 8, "max_hp": 8,
		"attack": 2, "defense": 0, "speed": 50.0,
		"skill_points": 0,
		"revive_tokens": 7,
	}
	var sd := KittenSaveData.from_dict(legacy)
	assert_not_null(sd, "legacy save with revive_tokens key loaded without error")
	assert_eq(sd.character_name, "Old", "other fields still hydrated")

func test_to_dict_does_not_emit_revive_tokens_key():
	# Pin the emit side of the contract: even when serializing a kitten,
	# the dict must not carry `revive_tokens` — otherwise a fresh save
	# would re-introduce the dead field for a future loader to handle.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var sd := KittenSaveData.from_character(c)
	assert_false(sd.to_dict().has("revive_tokens"),
		"to_dict must not emit the removed revive_tokens field")

# --- GameState wiring -------------------------------------------------------

func test_game_state_offline_xp_tracker_defaults_non_null():
	# Always-non-null contract — the kill flow reads .pending_xp without a
	# null check on autoload init.
	var gs := get_node("/root/GameState")
	assert_not_null(gs.offline_xp_tracker, "always non-null on autoload init")

func test_game_state_clear_resets_offline_xp_tracker():
	# clear() must drop a stale tracker so a logout / character-reset
	# starts the counter fresh — otherwise a sign-out followed by a
	# different account's first kill would merge the wrong pending_xp
	# into the new account's server save.
	var gs := get_node("/root/GameState")
	var saved: OfflineXPTracker = gs.offline_xp_tracker
	gs.offline_xp_tracker = OfflineXPTracker.new()
	gs.offline_xp_tracker.record(99)
	gs.clear()
	assert_not_null(gs.offline_xp_tracker, "still non-null after clear")
	assert_eq(gs.offline_xp_tracker.pending_xp, 0, "tracker is reset to a fresh instance")
	# Restore (after_each will also clear, but be explicit).
	gs.offline_xp_tracker = saved

# --- SaveManager round-trip with tracker ------------------------------------

func test_save_manager_writes_and_loads_offline_xp_earned():
	# End-to-end: a tracker with N pending XP round-trips through a
	# SaveManager.save / load cycle and a fresh tracker hydrated from
	# the loaded save reads N back.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pebbles")
	var t := OfflineXPTracker.new()
	t.record(31)
	var err := SaveManager.save(c, TMP_PATH, null, null, t)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	assert_eq(loaded.offline_xp_earned, 31)
	var restored := loaded.to_offline_xp_tracker()
	assert_eq(restored.pending_xp, 31)

# --- AccountManager.sign_out safety -----------------------------------------

func test_sign_out_does_not_delete_local_save_file():
	# Issue scenario 5: AccountManager.sign_out() does NOT delete the
	# local save file. Locks the contract that signing out of the
	# cloud account never erases a player's local kitten.
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN, "Shadow")
	SaveManager.save(c, TMP_PATH)
	assert_true(FileAccess.file_exists(TMP_PATH), "save file exists after write")

	var am := AccountManager.new(TMP_PATH)
	am.sign_in("user-123")
	assert_true(am.is_signed_in())

	am.sign_out()
	assert_false(am.is_signed_in(), "in-memory state cleared")
	assert_true(FileAccess.file_exists(TMP_PATH), "save file still present after sign_out")

	# And re-load the save to confirm it's not just an empty file lying around.
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded, "save file is still readable")
	assert_eq(loaded.character_name, "Shadow")

# --- AccountManager state machine -------------------------------------------

func test_sign_in_sets_signed_in_and_user_id():
	var am := AccountManager.new()
	assert_false(am.is_signed_in(), "starts signed out")
	assert_eq(am.user_id, "")
	assert_true(am.sign_in("u-1"))
	assert_true(am.is_signed_in())
	assert_eq(am.user_id, "u-1")

func test_sign_in_rejects_empty_user_id():
	var am := AccountManager.new()
	assert_false(am.sign_in(""), "empty user_id rejected")
	assert_false(am.is_signed_in())

func test_sign_in_idempotent_for_same_user():
	var am := AccountManager.new()
	am.sign_in("u-1")
	assert_false(am.sign_in("u-1"), "re-signing in same user returns false")
	assert_true(am.is_signed_in())

func test_sign_out_idempotent_when_already_signed_out():
	var am := AccountManager.new()
	assert_false(am.sign_out(), "no-op when not signed in")
	am.sign_in("u-1")
	assert_true(am.sign_out())
	assert_false(am.sign_out(), "second sign_out is no-op")

# --- SaveSyncOrchestrator ---------------------------------------------------

func test_sync_returns_null_when_both_inputs_null():
	# No save anywhere. No tracker clear (a transient fetch failure that
	# hands null for server should not erase pending offline XP — the
	# next attempt re-merges fresh).
	var t := OfflineXPTracker.new()
	t.record(7)
	assert_null(SaveSyncOrchestrator.sync(null, null, t))
	assert_eq(t.pending_xp, 7, "tracker untouched when both inputs null")

func test_sync_returns_clone_of_server_when_local_null():
	# Brand-new device: server is canonical. No local gameplay to fold;
	# tracker is empty by convention on a fresh install.
	var server := KittenSaveData.new()
	server.level = 4
	server.xp = 12
	server.character_name = "Cloud"
	var merged := SaveSyncOrchestrator.sync(null, server)
	assert_not_null(merged)
	assert_eq(merged.level, 4)
	assert_eq(merged.xp, 12)
	assert_eq(merged.character_name, "Cloud")

func test_sync_with_local_null_returns_clone_not_server_reference():
	# Mutating the merged result must not stealth-mutate the server input.
	var server := KittenSaveData.new()
	server.xp = 10
	var merged := SaveSyncOrchestrator.sync(null, server)
	merged.xp = 999
	assert_eq(server.xp, 10, "server input unchanged after merged result mutation")

func test_sync_with_local_null_does_not_clear_tracker():
	# Brand-new-device path has nothing to flush. Tracker should be empty
	# already (this is a fresh install context) but if it's not, leave it
	# alone — the call site can decide whether to drop it.
	var server := KittenSaveData.new()
	server.level = 1
	var t := OfflineXPTracker.new()
	t.record(5)
	SaveSyncOrchestrator.sync(null, server, t)
	assert_eq(t.pending_xp, 5, "local-null branch leaves tracker alone")

func test_sync_returns_clone_of_local_when_server_null():
	# Brand-new account / first sync-up: local is the upload payload.
	var local := KittenSaveData.new()
	local.level = 6
	local.xp = 8
	local.character_name = "Upload"
	var merged := SaveSyncOrchestrator.sync(local, null)
	assert_not_null(merged)
	assert_eq(merged.level, 6)
	assert_eq(merged.xp, 8)
	assert_eq(merged.character_name, "Upload")

func test_sync_with_server_null_returns_clone_not_local_reference():
	var local := KittenSaveData.new()
	local.xp = 10
	var merged := SaveSyncOrchestrator.sync(local, null)
	merged.xp = 999
	assert_eq(local.xp, 10, "local input unchanged after merged result mutation")

func test_sync_with_server_null_clears_tracker():
	# First sync-up uploads local; the offline window just settled, so
	# the tracker resets so the next solo kill starts fresh.
	var local := KittenSaveData.new()
	local.level = 3
	var t := OfflineXPTracker.new()
	t.record(11)
	SaveSyncOrchestrator.sync(local, null, t)
	assert_eq(t.pending_xp, 0, "first-sync-up clears tracker")

func test_sync_equal_level_folds_offline_xp_into_server():
	# The headline merge case: local earned XP offline at the same level
	# the server last saw. merge_xp folds it into the server clone so
	# the upload includes the offline gain.
	var local := KittenSaveData.new()
	local.level = 5
	local.xp = 18
	local.offline_xp_earned = 8
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 10
	var merged := SaveSyncOrchestrator.sync(local, server)
	assert_eq(merged.level, 5)
	assert_eq(merged.xp, 18, "server.xp + local.offline_xp_earned (10 + 8 = 18)")
	assert_eq(local.xp, 18, "local input not mutated")
	assert_eq(server.xp, 10, "server input not mutated")

func test_sync_equal_level_clears_tracker():
	# The merge folded pending_xp in; clearing it prevents the next sync
	# from double-counting the same delta.
	var local := KittenSaveData.new()
	local.level = 5
	local.xp = 18
	local.offline_xp_earned = 8
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 10
	var t := OfflineXPTracker.new()
	t.record(8)
	SaveSyncOrchestrator.sync(local, server, t)
	assert_eq(t.pending_xp, 0, "tracker cleared after merge")

func test_sync_local_higher_level_wins():
	# Local leveled up offline; resolve picks local. Offline XP delta is
	# already baked into local.xp / local.level so merge_xp is not called.
	var local := KittenSaveData.new()
	local.level = 7
	local.xp = 4
	local.offline_xp_earned = 25
	local.character_name = "Aheadlocal"
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 10
	server.character_name = "Behindcloud"
	var merged := SaveSyncOrchestrator.sync(local, server)
	assert_eq(merged.level, 7)
	assert_eq(merged.xp, 4, "local.xp preserved (offline xp already baked in)")
	assert_eq(merged.character_name, "Aheadlocal")

func test_sync_server_higher_level_wins():
	# Another device played further; server wins outright. Local's
	# offline_xp_earned is being abandoned along with the rest of local's
	# progression below server's level — it's not double-applied.
	var local := KittenSaveData.new()
	local.level = 4
	local.xp = 2
	local.offline_xp_earned = 12
	var server := KittenSaveData.new()
	server.level = 8
	server.xp = 30
	server.character_name = "Otherdevice"
	var merged := SaveSyncOrchestrator.sync(local, server)
	assert_eq(merged.level, 8)
	assert_eq(merged.xp, 30, "server.xp preserved; local offline delta NOT folded across level boundary")
	assert_eq(merged.character_name, "Otherdevice")

func test_sync_clears_tracker_even_when_server_wins():
	# When server wins, local progression is abandoned. The tracker's
	# pending_xp is part of that abandoned progression, so clearing
	# matches the abandonment — the next "since last sync" window starts
	# at zero.
	var local := KittenSaveData.new()
	local.level = 4
	var server := KittenSaveData.new()
	server.level = 8
	var t := OfflineXPTracker.new()
	t.record(12)
	SaveSyncOrchestrator.sync(local, server, t)
	assert_eq(t.pending_xp, 0, "server-wins branch still clears tracker")

func test_sync_returns_clone_decoupled_from_server_at_equal_level():
	# Mutating the merged result must not stealth-mutate the server input.
	var local := KittenSaveData.new()
	local.level = 5
	local.offline_xp_earned = 3
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 10
	var merged := SaveSyncOrchestrator.sync(local, server)
	merged.xp = 999
	assert_eq(server.xp, 10, "server input unchanged after merged result mutation")

func test_sync_returns_clone_decoupled_from_local_when_local_wins():
	var local := KittenSaveData.new()
	local.level = 7
	local.xp = 5
	var server := KittenSaveData.new()
	server.level = 5
	var merged := SaveSyncOrchestrator.sync(local, server)
	merged.xp = 999
	assert_eq(local.xp, 5, "local input unchanged after merged result mutation")

func test_sync_null_tracker_arg_is_safe():
	# Tracker is optional — call sites that don't have one (test paths,
	# pre-#15-merge fallback) should work cleanly.
	var local := KittenSaveData.new()
	local.level = 3
	var server := KittenSaveData.new()
	server.level = 3
	var merged := SaveSyncOrchestrator.sync(local, server, null)
	assert_not_null(merged)
	assert_eq(merged.level, 3)

func test_sync_zero_offline_xp_is_clean_noop_at_equal_level():
	# Player signed in without any offline activity since last sync. The
	# merge is a no-op on the xp side; tracker is already empty so the
	# clear is also a no-op. Locks the "no-side-effect for a no-op sync"
	# contract — important because the wire layer may call sync() on
	# every sign-in even when nothing changed.
	var local := KittenSaveData.new()
	local.level = 4
	local.xp = 5
	local.offline_xp_earned = 0
	var server := KittenSaveData.new()
	server.level = 4
	server.xp = 5
	var t := OfflineXPTracker.new()
	var merged := SaveSyncOrchestrator.sync(local, server, t)
	assert_eq(merged.xp, 5)
	assert_eq(merged.level, 4)
	assert_eq(t.pending_xp, 0, "tracker stays empty")

func test_sync_end_to_end_with_save_manager_round_trip():
	# Realistic path: write a local save with offline XP via SaveManager,
	# load it back, build a server save at equal level with less XP, sync,
	# then write the merged result back. Confirms the orchestrator slots
	# into the SaveManager round-trip without lossy conversions.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Round")
	c.level = 5
	c.xp = 20
	var t := OfflineXPTracker.new()
	t.record(6)
	SaveManager.save(c, TMP_PATH, null, null, t)
	var local := SaveManager.load(TMP_PATH)
	var server := KittenSaveData.new()
	server.level = 5
	server.xp = 14
	server.character_name = "Round"
	var merged := SaveSyncOrchestrator.sync(local, server, t)
	assert_eq(merged.xp, 20, "server.xp(14) + local.offline_xp_earned(6) = 20")
	assert_eq(t.pending_xp, 0, "tracker cleared after sync")
