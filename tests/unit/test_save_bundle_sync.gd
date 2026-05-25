extends GutTest

# Slice 6 of PRD #250: SaveSyncOrchestrator.sync over SaveBundle.
# Account-wide fields union/max; per-slot fields reuse the level-based
# resolve + merge_xp semantics from the kitten path.

func _wizard_slot(level: int, xp: int = 0, offline_xp: int = 0) -> CharacterSlotData:
	var s := CharacterSlotData.new()
	s.character_class = int(CharacterData.CharacterClass.WIZARD_KITTEN)
	s.character_name = "Mittens"
	s.level = level
	s.xp = xp
	s.offline_xp_earned = offline_xp
	return s

func _battle_slot(level: int = 1) -> CharacterSlotData:
	var s := CharacterSlotData.new()
	s.character_class = int(CharacterData.CharacterClass.BATTLE_KITTEN)
	s.character_name = "Tank"
	s.level = level
	return s

func test_per_slot_offline_xp_merges_at_equal_level():
	# Equal level wizard slot on both sides: local.offline_xp_earned (50)
	# folds into server.xp (100) -> merged xp == 150.
	var local := SaveBundle.new()
	local.slots[SaveBundle.SLOT_WIZARD] = _wizard_slot(5, 0, 50)
	var server := SaveBundle.new()
	server.slots[SaveBundle.SLOT_WIZARD] = _wizard_slot(5, 100, 0)
	var merged: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, server)
	assert_not_null(merged)
	var ws: CharacterSlotData = merged.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(ws, "wizard slot present after merge")
	assert_eq(ws.level, 5)
	assert_eq(ws.xp, 150, "server.xp(100) + local.offline_xp_earned(50)")

func test_unlock_sets_are_unioned():
	# paid_class_unlocks, cosmetic_packs, skill_unlocks all union — purchases
	# on either device must not be lost.
	var local := SaveBundle.new()
	local.account.paid_class_unlocks = ["wizard_cat"]
	local.account.cosmetic_packs = ["pack_a"]
	local.account.skill_unlocks = ["skill_x"]
	var server := SaveBundle.new()
	server.account.paid_class_unlocks = ["battle_cat"]
	server.account.cosmetic_packs = ["pack_b"]
	server.account.skill_unlocks = ["skill_y"]
	var merged: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, server)
	var paid = merged.account.paid_class_unlocks
	assert_true(paid.has("wizard_cat") and paid.has("battle_cat"),
		"paid_class_unlocks union has both sides")
	var packs = merged.account.cosmetic_packs
	assert_true(packs.has("pack_a") and packs.has("pack_b"),
		"cosmetic_packs union has both sides")
	var skills = merged.account.skill_unlocks
	assert_true(skills.has("skill_x") and skills.has("skill_y"),
		"skill_unlocks union has both sides")

func test_streak_and_meta_take_max():
	# streak_day takes max; max_level_per_class takes per-class max.
	var local := SaveBundle.new()
	local.account.streak_day = 2
	local.account.max_level_per_class = {"wizard_kitten": 4}
	var server := SaveBundle.new()
	server.account.streak_day = 5
	server.account.max_level_per_class = {"wizard_kitten": 7}
	var merged: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, server)
	assert_eq(merged.account.streak_day, 5)
	assert_eq(int(merged.account.max_level_per_class["wizard_kitten"]), 7)

func test_slot_only_on_one_side_carries_through():
	# Local has battle slot, server does not. Merged bundle must still have
	# the battle slot (with the same level), unchanged.
	var local := SaveBundle.new()
	local.slots[SaveBundle.SLOT_BATTLE] = _battle_slot(3)
	var server := SaveBundle.new()
	var merged: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, server)
	var bs: CharacterSlotData = merged.get_slot(SaveBundle.SLOT_BATTLE)
	assert_not_null(bs, "battle slot carried through from local-only side")
	assert_eq(bs.level, 3)

func test_differing_slot_level_higher_wins():
	# Wizard local level 3 vs server level 6 → merged wizard reflects level 6.
	var local := SaveBundle.new()
	local.slots[SaveBundle.SLOT_WIZARD] = _wizard_slot(3, 0, 99)
	var server := SaveBundle.new()
	server.slots[SaveBundle.SLOT_WIZARD] = _wizard_slot(6, 42, 0)
	var merged: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, server)
	var ws: CharacterSlotData = merged.get_slot(SaveBundle.SLOT_WIZARD)
	assert_eq(ws.level, 6, "higher level wins")
	assert_eq(ws.xp, 42, "winner's xp preserved; loser's offline delta abandoned")

func test_null_inputs_mirror_legacy():
	# Both null → null; one null → clone of the other.
	assert_null(SaveSyncOrchestrator.sync_bundle(null, null), "both null returns null")
	var server := SaveBundle.new()
	server.account.gold_balance = 75
	server.slots[SaveBundle.SLOT_WIZARD] = _wizard_slot(2, 3)
	var merged_a: SaveBundle = SaveSyncOrchestrator.sync_bundle(null, server)
	assert_not_null(merged_a)
	assert_eq(merged_a.account.gold_balance, 75, "server-only path clones account")
	assert_not_null(merged_a.get_slot(SaveBundle.SLOT_WIZARD))
	# Mutating merged must not stealth-mutate server input.
	merged_a.account.gold_balance = 999
	assert_eq(server.account.gold_balance, 75, "server input unchanged after merged mutation")
	var local := SaveBundle.new()
	local.account.gold_balance = 22
	var merged_b: SaveBundle = SaveSyncOrchestrator.sync_bundle(local, null)
	assert_not_null(merged_b)
	assert_eq(merged_b.account.gold_balance, 22, "local-only path clones account")

func test_sync_returns_save_bundle_type():
	# Type-dispatch sanity: passing bundles produces a SaveBundle (not a
	# KittenSaveData via the legacy path).
	var local := SaveBundle.new()
	var server := SaveBundle.new()
	var merged = SaveSyncOrchestrator.sync_bundle(local, server)
	assert_true(merged is SaveBundle, "bundle inputs produce a SaveBundle")
