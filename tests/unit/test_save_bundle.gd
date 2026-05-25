extends GutTest

# Slice 1 (PRD #250 / issue #251): the SaveBundle data layer. Covers
# AccountSaveData + CharacterSlotData round-trips, archetype slot keying
# (Cat collapses to its Kitten's slot), and legacy flat-save discard.

const TMP_PATH := "user://test_save_bundle.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func test_bundle_round_trips_account_gold_and_slot_level():
	# Core wiring: a populated bundle survives to_dict → from_dict with both
	# the account-wide gold and the per-slot level preserved.
	var bundle := SaveBundle.new()
	bundle.account.gold_balance = 250
	var slot := CharacterSlotData.new()
	slot.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	slot.level = 3
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, slot)

	var d := bundle.to_dict()
	var loaded := SaveBundle.from_dict(d)

	assert_eq(loaded.account.gold_balance, 250)
	var wiz: CharacterSlotData = loaded.get_slot(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_not_null(wiz, "wizard slot should be present after round-trip")
	assert_eq(wiz.level, 3)

func test_round_trips_all_account_and_slot_fields():
	# Content details: every account and per-character field survives a
	# round-trip with no loss.
	var bundle := SaveBundle.new()
	bundle.account.gem_balance = 17
	bundle.account.paid_class_unlocks = ["wizard_cat"]
	bundle.account.cosmetic_packs = ["pack_a"]
	bundle.account.max_level_per_class = {"wizard_kitten": 6}
	bundle.account.dungeons_completed = 4
	bundle.account.cleared_dungeons = ["d1"]
	bundle.account.streak_day = 3
	bundle.account.last_login_date = "2026-05-25"

	var slot := CharacterSlotData.new()
	slot.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	slot.appearance_index = 0
	slot.unlocked_skill_ids = ["s1", "s2"]
	slot.equipped_items = {0: "sword"}
	slot.item_bag = ["potion"]
	slot.quickbar_slots = ["fireball", "", "", ""]
	slot.dungeon_run_state = {"seed": 99}
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, slot)

	var loaded := SaveBundle.from_dict(bundle.to_dict())

	assert_eq(loaded.account.gem_balance, 17)
	assert_true(loaded.account.paid_class_unlocks.has("wizard_cat"))
	assert_true(loaded.account.cosmetic_packs.has("pack_a"))
	assert_eq(int(loaded.account.max_level_per_class.get("wizard_kitten", -1)), 6)
	assert_eq(loaded.account.dungeons_completed, 4)
	assert_true(loaded.account.cleared_dungeons.has("d1"))
	assert_eq(loaded.account.streak_day, 3)
	assert_eq(loaded.account.last_login_date, "2026-05-25")

	var wiz: CharacterSlotData = loaded.get_slot(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_not_null(wiz)
	assert_eq(wiz.appearance_index, 0)
	assert_eq(wiz.unlocked_skill_ids, ["s1", "s2"])
	assert_eq(String(wiz.equipped_items.get(0, "")), "sword")
	assert_eq(wiz.item_bag, ["potion"])
	assert_eq(wiz.quickbar_slots, ["fireball", "", "", ""])
	assert_eq(int(wiz.dungeon_run_state.get("seed", -1)), 99)

func test_cat_and_kitten_share_archetype_slot_key():
	# Wizard Cat collapses to the Wizard Kitten's slot so an in-place
	# evolution keeps the slot's save.
	assert_eq(
		SaveBundle.slot_key_for_class(CharacterData.CharacterClass.WIZARD_CAT),
		SaveBundle.slot_key_for_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	)
	# The four kitten classes map to four distinct keys.
	var keys := {}
	for k in [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]:
		keys[SaveBundle.slot_key_for_class(k)] = true
	assert_eq(keys.size(), 4, "four kitten archetypes should yield four distinct slot keys")

func test_legacy_flat_save_is_discarded():
	# A pre-rework flat save (no version/slots keys) is detected as legacy
	# and discarded — load_bundle yields a fresh empty bundle, not a crash.
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"character_name": "Old", "level": 9}))
	f.close()

	var loaded := SaveManager.load_bundle(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.occupied_slot_keys().size(), 0,
		"legacy flat save should yield zero occupied slots")
	assert_eq(loaded.account.gold_balance, 0,
		"legacy flat save should not bleed values into the empty bundle")

	# Equivalent to from_dict({}) — both produce a fresh empty bundle.
	var empty := SaveBundle.from_dict({})
	assert_eq(loaded.occupied_slot_keys().size(), empty.occupied_slot_keys().size())
	assert_eq(loaded.account.gold_balance, empty.account.gold_balance)

func test_save_manager_bundle_file_round_trip():
	# SaveManager writes the bundle to a single file and reads it back equal.
	var bundle := SaveBundle.new()
	bundle.account.gold_balance = 77
	var slot := CharacterSlotData.new()
	slot.character_name = "Whiskers"
	slot.character_class = CharacterData.CharacterClass.BATTLE_KITTEN
	slot.level = 5
	bundle.set_slot(CharacterData.CharacterClass.BATTLE_KITTEN, slot)

	var err: Error = SaveManager.save_bundle(bundle, TMP_PATH)
	assert_eq(err, OK)
	assert_true(FileAccess.file_exists(TMP_PATH))

	var loaded := SaveManager.load_bundle(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.account.gold_balance, 77)
	var battle: CharacterSlotData = loaded.get_slot(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_not_null(battle)
	assert_eq(battle.character_name, "Whiskers")
	assert_eq(battle.level, 5)
