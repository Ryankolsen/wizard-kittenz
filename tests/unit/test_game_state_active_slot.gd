extends GutTest

# Slice 2 (PRD #250 / issue #252) — GameState active-slot hydration and
# bundle assembly. Pins that save_from_state writes the live state into the
# active slot of a SaveBundle (and account-wide fields onto AccountSaveData),
# that other slots survive a save, and that the hydrate path lights up
# account-wide fields even with no active character.

const TMP_PATH := "user://test_gs_active_slot.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	if FileAccess.file_exists(SaveManager.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.DEFAULT_PATH))
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _make_wizard(level: int = 3) -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Mittens"
	c.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	c.level = level
	c.max_hp = 20
	c.hp = 18
	c.attack = 7
	return c

func test_save_from_state_writes_character_to_slot_and_gold_to_account():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_wizard(3)
	gs.currency_ledger.credit(250, CurrencyLedger.Currency.GOLD)

	var err: Error = SaveManager.save_from_state(TMP_PATH)
	assert_eq(err, OK)

	var bundle := SaveManager.load_bundle(TMP_PATH)
	assert_not_null(bundle)
	assert_eq(bundle.active_slot, SaveBundle.SLOT_WIZARD)
	var slot := bundle.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(slot, "wizard slot must be written")
	assert_eq(slot.level, 3, "active slot level must match live character")
	assert_eq(bundle.account.gold_balance, 250,
		"gold lives on the account, not the slot")

func test_save_from_state_preserves_other_slots():
	# Pre-populate the bundle with an occupied battle slot at level 5.
	var seed_bundle := SaveBundle.new()
	var battle_slot := CharacterSlotData.new()
	battle_slot.character_name = "Brawler"
	battle_slot.character_class = CharacterData.CharacterClass.BATTLE_KITTEN
	battle_slot.level = 5
	seed_bundle.set_slot(CharacterData.CharacterClass.BATTLE_KITTEN, battle_slot)
	seed_bundle.active_slot = SaveBundle.SLOT_BATTLE
	assert_eq(SaveManager.save_bundle(seed_bundle, TMP_PATH), OK)

	# Now save a wizard active character — the battle slot must survive.
	var gs := get_node("/root/GameState")
	gs.current_character = _make_wizard(2)
	assert_eq(SaveManager.save_from_state(TMP_PATH), OK)

	var reloaded := SaveManager.load_bundle(TMP_PATH)
	var battle_after := reloaded.get_slot(SaveBundle.SLOT_BATTLE)
	assert_not_null(battle_after, "battle slot must still exist after wizard save")
	assert_eq(battle_after.level, 5, "battle slot level must be untouched")
	var wizard_after := reloaded.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(wizard_after, "wizard slot must be written by save_from_state")

func test_account_hydrates_without_character():
	var bundle := SaveBundle.new()
	bundle.account.gold_balance = 99
	# No slots occupied; active_slot stays "".
	var gs := get_node("/root/GameState")
	gs.hydrate_from_bundle(bundle)
	assert_eq(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD), 99,
		"account gold must hydrate even with no active character")
	assert_null(gs.current_character,
		"current_character stays null when no slot is active (menu state)")

func test_switch_to_slot_swaps_character_keeps_account():
	# Slice 3 (#253): seed two occupied slots on disk and switch between
	# them. Account-wide live state (gold) must survive the swap; the
	# outgoing slot must be persisted before the new one hydrates.
	var seed_bundle := SaveBundle.new()
	var battle_slot := CharacterSlotData.new()
	battle_slot.character_name = "Brawler"
	battle_slot.character_class = CharacterData.CharacterClass.BATTLE_KITTEN
	battle_slot.level = 5
	seed_bundle.set_slot(CharacterData.CharacterClass.BATTLE_KITTEN, battle_slot)
	var wiz_slot := CharacterSlotData.new()
	wiz_slot.character_name = "Mittens"
	wiz_slot.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	wiz_slot.level = 3
	seed_bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, wiz_slot)
	seed_bundle.active_slot = SaveBundle.SLOT_WIZARD
	assert_eq(SaveManager.save_bundle(seed_bundle, SaveManager.DEFAULT_PATH), OK)

	var gs := get_node("/root/GameState")
	gs.hydrate_from_bundle(SaveManager.load_bundle())
	gs.currency_ledger.credit(300, CurrencyLedger.Currency.GOLD)

	gs.switch_to_slot(SaveBundle.SLOT_BATTLE)

	assert_not_null(gs.current_character)
	assert_eq(gs.current_character.character_class,
		CharacterData.CharacterClass.BATTLE_KITTEN,
		"current character should now be the battle one")
	assert_eq(gs.current_character.level, 5,
		"battle slot was level 5 on disk")
	assert_eq(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD), 300,
		"account gold should survive the slot switch")

	# Persist again and reload — the wizard slot should still be at level 3,
	# proving the outgoing slot was saved before the switch.
	SaveManager.save_from_state()
	var reloaded := SaveManager.load_bundle()
	var wiz_after := reloaded.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(wiz_after, "wizard slot must still exist after switch+save")
	assert_eq(wiz_after.level, 3, "wizard slot level must be preserved")

func test_empty_bundle_leaves_menu_state():
	var bundle := SaveBundle.new()
	var gs := get_node("/root/GameState")
	gs.hydrate_from_bundle(bundle)
	assert_null(gs.current_character,
		"empty bundle must leave current_character null")
	assert_eq(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD), 0,
		"empty bundle yields zero gold")
	assert_eq(gs.meta_tracker.dungeons_completed, 0,
		"empty bundle yields zero meta progression")
