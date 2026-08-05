extends GutTest

# Call-site wiring for the 4 test achievements (PRD #446 / issue #449). The
# unlock/dedup logic itself is AchievementService's job and already covered
# by test_achievement_service.gd (#447); these tests only pin that each
# trigger point actually calls GameState.achievement_service.record_event
# with the right event key when the underlying action succeeds.

func before_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())

func after_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())
	GameState.current_character = null
	if FileAccess.file_exists(SaveManager.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.DEFAULT_PATH))

# --- Content details ---------------------------------------------------------

func test_catalog_has_seven_entries_with_valid_content():
	var defs := AchievementCatalog.all()
	assert_eq(defs.size(), 7)
	for d in defs:
		assert_false(d.title.is_empty(), "%s must have a non-empty title" % d.id)
		assert_false(d.flavor_text.is_empty(), "%s must have non-empty flavor text" % d.id)
		if d.reward_type == AchievementDefinition.RewardType.GOLD:
			assert_true(d.reward_amount > 0, "%s gold reward must be > 0" % d.id)
		elif d.reward_type == AchievementDefinition.RewardType.POTION:
			assert_not_null(PotionCatalog.find(d.reward_potion_id),
				"%s potion reward '%s' must resolve in PotionCatalog" % [d.id, d.reward_potion_id])
		elif d.reward_type == AchievementDefinition.RewardType.TOME:
			var tree := SkillTree.make_battle_kitten_tree()
			var node := tree.find(d.reward_node_id)
			assert_not_null(node, "%s tome reward node '%s' must resolve in SkillTree" % [d.id, d.reward_node_id])
			if node != null:
				assert_not_null(node.spell, "%s tome reward node '%s' must carry a spell" % [d.id, d.reward_node_id])
				assert_eq(node.spell.id, d.reward_spell_id,
					"%s tome reward spell id must match the unlocked node's spell" % d.id)

# --- Content details: enemies-killed tier thresholds --------------------------

func test_enemies_killed_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("enemies_killed", 9)
	assert_false(service.account.achievement_state.has("mouse_patrol"), "9 kills must not unlock Mouse Patrol")
	service.increment_counter("enemies_killed", 1)
	assert_true(service.account.achievement_state.has("mouse_patrol"), "10 kills unlocks Mouse Patrol")
	assert_false(service.account.achievement_state.has("certified_menace"))
	service.increment_counter("enemies_killed", 90)
	assert_true(service.account.achievement_state.has("certified_menace"), "100 kills unlocks Certified Menace")
	assert_false(service.account.achievement_state.has("apex_predator_probably"))
	service.increment_counter("enemies_killed", 900)
	assert_true(service.account.achievement_state.has("apex_predator_probably"), "1,000 kills unlocks Apex Predator (Probably)")

func test_enemies_killed_tiers_have_correct_thresholds_and_ids():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["mouse_patrol"].threshold, 10)
	assert_eq(by_id["mouse_patrol"].counter_key, "enemies_killed")
	assert_eq(by_id["certified_menace"].threshold, 100)
	assert_eq(by_id["apex_predator_probably"].threshold, 1000)

# --- Core wiring: rename cat --------------------------------------------------

func _instantiate_creation_scene() -> Node:
	GameState.current_character = null
	GameState.meta_tracker = MetaProgressionTracker.new()
	GameState.unlock_registry = UnlockRegistry.make_default()
	var scene = load("res://scenes/character_creation.tscn").instantiate()
	add_child_autofree(scene)
	return scene

func test_rename_cat_triggers_achievement():
	var scene := _instantiate_creation_scene()
	GameState.current_character = CharacterData.make_new(
		CharacterData.CharacterClass.WIZARD_KITTEN, "Old Name")
	var name_edit := scene.get_node("Customize/VBox/NameRow/NameEdit") as LineEdit
	name_edit.text = "New Name"
	var save_btn := scene.find_child("SaveButton", true, false) as Button
	save_btn.pressed.emit()
	assert_true(GameState.achievement_service.account.achievement_state.has("first_rename"),
		"renaming a cat must record the cat_renamed event")

func test_rename_cat_twice_does_not_reunlock():
	var scene := _instantiate_creation_scene()
	GameState.current_character = CharacterData.make_new(
		CharacterData.CharacterClass.WIZARD_KITTEN, "Old Name")
	watch_signals(GameState.achievement_service)
	var name_edit := scene.get_node("Customize/VBox/NameRow/NameEdit") as LineEdit
	var save_btn := scene.find_child("SaveButton", true, false) as Button
	name_edit.text = "New Name"
	save_btn.pressed.emit()
	name_edit.text = "Yet Another Name"
	save_btn.pressed.emit()
	assert_signal_emit_count(GameState.achievement_service, "achievement_unlocked", 1,
		"a second rename must not re-unlock first_rename")

# --- Core wiring: enter dungeon -----------------------------------------------

func test_dungeon_entered_triggers_achievement():
	var controller := DungeonRunController.new()
	var dungeon := DungeonGenerator.generate(12345)
	var ok := controller.start(dungeon)
	assert_true(ok)
	assert_true(GameState.achievement_service.account.achievement_state.has("first_dungeon"),
		"starting a dungeon run must record the dungeon_entered event")

func test_dungeon_entered_failed_start_does_not_trigger():
	var controller := DungeonRunController.new()
	var ok := controller.start(null)
	assert_false(ok)
	assert_false(GameState.achievement_service.account.achievement_state.has("first_dungeon"),
		"a failed start() must not record the dungeon_entered event")

# --- Core wiring: open chest --------------------------------------------------

func test_chest_opened_triggers_achievement():
	var entity := ChestEntity.new()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ok := entity.open("p1", CharacterFactory.create_default("Mage"), rng)
	assert_true(ok)
	assert_true(GameState.achievement_service.account.achievement_state.has("first_chest"),
		"opening a chest must record the chest_opened event")
	entity.free()

# --- Core wiring: kill mob ----------------------------------------------------

func _make_enemy() -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	return e

func test_enemy_killed_triggers_achievement():
	var e := _make_enemy()
	e.apply_state_update(1000.0)
	e.data.hp = 0
	e.apply_state_update(10.0)
	assert_true(GameState.achievement_service.account.achievement_state.has("first_kill"),
		"an enemy dying must record the enemy_killed event")
	e.free()

func test_enemy_killed_also_increments_enemies_killed_counter():
	var e := _make_enemy()
	e.apply_state_update(1000.0)
	e.data.hp = 0
	e.apply_state_update(10.0)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("enemies_killed", 0)), 1,
		"an enemy dying must also increment the enemies_killed counter")
	e.free()

func test_enemy_killed_twice_does_not_reunlock():
	var e1 := _make_enemy()
	e1.data.hp = 0
	e1.apply_state_update(10.0)
	var e2 := _make_enemy()
	e2.data.hp = 0
	watch_signals(GameState.achievement_service)
	e2.apply_state_update(10.0)
	assert_signal_not_emitted(GameState.achievement_service, "achievement_unlocked",
		"a second enemy death must not re-unlock first_kill (record_event's own dedup)")
	e1.free()
	e2.free()
