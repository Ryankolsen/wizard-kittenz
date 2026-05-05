extends GutTest

const TMP_PATH := "user://test_save_sync.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# --- SaveManager round-trip -------------------------------------------------

func test_save_manager_writes_and_loads_with_identical_level_and_xp():
	# Issue scenario 1: Core wiring — SaveManager.save writes to disk
	# and SaveManager.load returns data with identical level and xp.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Mittens")
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

# --- AccountManager.sign_out safety -----------------------------------------

func test_sign_out_does_not_delete_local_save_file():
	# Issue scenario 5: AccountManager.sign_out() does NOT delete the
	# local save file. Locks the contract that signing out of the
	# cloud account never erases a player's local kitten.
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
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
