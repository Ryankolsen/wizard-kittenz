extends GutTest

# Slice 5 (PRD #250 / issue #255) — multiplayer character feed. Pins the
# AFK-testable seams of co-op character selection: the selected (active-slot)
# character is what feeds the CoopSession chars map, co-op rewards persist
# back to that slot + the account, and an empty slot can't enter multiplayer.
# Mirrors tests/unit/test_save_manager_from_state.gd (live /root/GameState).
# The live lobby/socket path is HITL-verified in QA #256.

const TMP_PATH := "user://test_coop_character_feed.json"

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

func test_coop_chars_map_uses_active_slot_character():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_wizard(3)
	gs.local_player_id = "p1"

	var chars: Dictionary = gs.build_coop_chars_map()

	assert_true(chars.has("p1"), "chars map keyed by local_player_id")
	var fed: CharacterData = chars["p1"]
	assert_not_null(fed, "the active slot character must feed the map")
	assert_eq(fed.level, 3, "the saved character's real level enters the match")
	assert_eq(fed.character_class, CharacterData.CharacterClass.WIZARD_KITTEN,
		"the selected archetype enters the match, not a default battle kitten")

func test_coop_rewards_persist_to_active_slot():
	var gs := get_node("/root/GameState")
	var wizard := _make_wizard(3)
	wizard.xp = 10
	gs.current_character = wizard
	gs.skill_tree = gs._build_tree_for(wizard)

	# Simulate a co-op match: XP lands on the active character's real_stats
	# (PartyMember.real_stats is the same CharacterData object the chars map
	# feeds in) and gold is credited to the account ledger.
	wizard.xp += 40
	gs.currency_ledger.credit(75, CurrencyLedger.Currency.GOLD)

	assert_eq(SaveManager.save_from_state(TMP_PATH), OK)

	var bundle := SaveManager.load_bundle(TMP_PATH)
	var slot := bundle.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(slot, "active wizard slot must be written")
	assert_eq(slot.xp, 50, "co-op XP must persist to the active slot")
	assert_eq(bundle.account.gold_balance, 75,
		"co-op gold must persist to the account save")

func test_empty_slot_blocks_multiplayer_entry():
	var bundle := SaveBundle.new()
	# Occupy only the wizard slot; the battle slot stays empty.
	var wiz_slot := CharacterSlotData.new()
	wiz_slot.character_name = "Mittens"
	wiz_slot.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	wiz_slot.level = 3
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, wiz_slot)

	assert_false(
		CharacterCreation.can_enter_multiplayer(bundle, SaveBundle.SLOT_BATTLE),
		"an empty slot can't join — the guard routes to creation first")
	assert_true(
		CharacterCreation.can_enter_multiplayer(bundle, SaveBundle.SLOT_WIZARD),
		"an occupied slot proceeds to the lobby")
