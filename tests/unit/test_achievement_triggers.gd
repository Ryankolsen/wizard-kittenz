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

func test_catalog_has_sixteen_entries_with_valid_content():
	var defs := AchievementCatalog.all()
	assert_eq(defs.size(), 34)
	for d in defs:
		assert_false(d.title.is_empty(), "%s must have a non-empty title" % d.id)
		assert_false(d.flavor_text.is_empty(), "%s must have non-empty flavor text" % d.id)
		if d.reward_type == AchievementDefinition.RewardType.GOLD:
			assert_true(d.reward_amount > 0, "%s gold reward must be > 0" % d.id)
		elif d.reward_type == AchievementDefinition.RewardType.POTION:
			assert_not_null(PotionCatalog.find(d.reward_potion_id),
				"%s potion reward '%s' must resolve in PotionCatalog" % [d.id, d.reward_potion_id])
		elif d.reward_type == AchievementDefinition.RewardType.ITEM:
			assert_not_null(ItemCatalog.find(d.reward_item_id),
				"%s item reward '%s' must resolve in ItemCatalog" % [d.id, d.reward_item_id])
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

# --- Content details: self-heal tier thresholds --------------------------------

func test_self_heal_tiers_unlock_at_correct_totals_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("self_heal_total", 99)
	assert_false(service.account.achievement_state.has("basic_tune_up"), "99 HP self-healed must not unlock Basic Tune-Up")
	service.increment_counter("self_heal_total", 1)
	assert_true(service.account.achievement_state.has("basic_tune_up"), "100 HP self-healed unlocks Basic Tune-Up")
	assert_false(service.account.achievement_state.has("field_medic"))
	service.increment_counter("self_heal_total", 900)
	assert_true(service.account.achievement_state.has("field_medic"), "1,000 HP self-healed unlocks Field Medic")
	assert_false(service.account.achievement_state.has("immortal_ish"))
	service.increment_counter("self_heal_total", 9000)
	assert_true(service.account.achievement_state.has("immortal_ish"), "10,000 HP self-healed unlocks Immortal-ish")

func test_self_heal_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["basic_tune_up"].threshold, 100)
	assert_eq(by_id["basic_tune_up"].counter_key, "self_heal_total")
	assert_eq(by_id["basic_tune_up"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["field_medic"].threshold, 1000)
	assert_eq(by_id["field_medic"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["immortal_ish"].threshold, 10000)
	assert_eq(by_id["immortal_ish"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["immortal_ish"].reward_item_id, "guardians_locket")

func test_self_heal_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("self_heal_total", 10000)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("basic_tune_up", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("field_medic", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("immortal_ish", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("guardians_locket"), "Immortal-ish must grant Guardian's Locket to the earning cat's bag")

# --- Content details: damage-dealt tier thresholds ------------------------------

func test_damage_dealt_tiers_unlock_at_correct_totals_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("damage_dealt", 999)
	assert_false(service.account.achievement_state.has("warming_up"), "999 damage dealt must not unlock Warming Up")
	service.increment_counter("damage_dealt", 1)
	assert_true(service.account.achievement_state.has("warming_up"), "1,000 damage dealt unlocks Warming Up")
	assert_false(service.account.achievement_state.has("certified_wrecking_ball"))
	service.increment_counter("damage_dealt", 9000)
	assert_true(service.account.achievement_state.has("certified_wrecking_ball"), "10,000 damage dealt unlocks Certified Wrecking Ball")
	assert_false(service.account.achievement_state.has("one_cat_apocalypse"))
	service.increment_counter("damage_dealt", 90000)
	assert_true(service.account.achievement_state.has("one_cat_apocalypse"), "100,000 damage dealt unlocks One-Cat Apocalypse")

func test_damage_dealt_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["warming_up"].threshold, 1000)
	assert_eq(by_id["warming_up"].counter_key, "damage_dealt")
	assert_eq(by_id["warming_up"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["certified_wrecking_ball"].threshold, 10000)
	assert_eq(by_id["certified_wrecking_ball"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["one_cat_apocalypse"].threshold, 100000)
	assert_eq(by_id["one_cat_apocalypse"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["one_cat_apocalypse"].reward_item_id, "executioners_signet")

func test_damage_dealt_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("damage_dealt", 100000)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("warming_up", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("certified_wrecking_ball", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("one_cat_apocalypse", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("executioners_signet"), "One-Cat Apocalypse must grant Executioner's Signet to the earning cat's bag")

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

func test_dungeon_entered_also_increments_dungeons_entered_counter():
	var controller := DungeonRunController.new()
	var dungeon := DungeonGenerator.generate(12345)
	controller.start(dungeon)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("dungeons_entered", 0)), 1,
		"starting a dungeon run must also increment the dungeons_entered counter")

func test_dungeon_entered_failed_start_does_not_trigger():
	var controller := DungeonRunController.new()
	var ok := controller.start(null)
	assert_false(ok)
	assert_false(GameState.achievement_service.account.achievement_state.has("first_dungeon"),
		"a failed start() must not record the dungeon_entered event")
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("dungeons_entered", 0)), 0,
		"a failed start() must not increment the dungeons_entered counter")

# --- Content details: dungeons-entered tier thresholds --------------------------

func test_dungeons_entered_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("dungeons_entered", 9)
	assert_false(service.account.achievement_state.has("frequent_flyer"), "9 dungeons must not unlock Frequent Flyer")
	service.increment_counter("dungeons_entered", 1)
	assert_true(service.account.achievement_state.has("frequent_flyer"), "10 dungeons unlocks Frequent Flyer")
	assert_false(service.account.achievement_state.has("dungeon_regular"))
	service.increment_counter("dungeons_entered", 40)
	assert_true(service.account.achievement_state.has("dungeon_regular"), "50 dungeons unlocks Dungeon Regular")
	assert_false(service.account.achievement_state.has("dungeon_landlord"))
	service.increment_counter("dungeons_entered", 150)
	assert_true(service.account.achievement_state.has("dungeon_landlord"), "200 dungeons unlocks Dungeon Landlord")

func test_dungeons_entered_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["frequent_flyer"].threshold, 10)
	assert_eq(by_id["frequent_flyer"].counter_key, "dungeons_entered")
	assert_eq(by_id["frequent_flyer"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["dungeon_regular"].threshold, 50)
	assert_eq(by_id["dungeon_regular"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["dungeon_landlord"].threshold, 200)
	assert_eq(by_id["dungeon_landlord"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["dungeon_landlord"].reward_item_id, "bramble_plate")

func test_dungeons_entered_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("dungeons_entered", 200)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("frequent_flyer", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("dungeon_regular", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("dungeon_landlord", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("bramble_plate"), "Dungeon Landlord must grant Bramble Plate to the earning cat's bag")

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
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("chests_opened", 0)), 1,
		"opening a chest must also increment the chests_opened counter")
	entity.free()

# --- Content details: chests-opened tier thresholds ------------------------------

func test_chests_opened_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("chests_opened", 9)
	assert_false(service.account.achievement_state.has("curious_cat"), "9 chests must not unlock Curious Cat")
	service.increment_counter("chests_opened", 1)
	assert_true(service.account.achievement_state.has("curious_cat"), "10 chests unlocks Curious Cat")
	assert_false(service.account.achievement_state.has("chest_goblin"))
	service.increment_counter("chests_opened", 90)
	assert_true(service.account.achievement_state.has("chest_goblin"), "100 chests unlocks Chest Goblin")
	assert_false(service.account.achievement_state.has("hoarder_in_training"))
	service.increment_counter("chests_opened", 400)
	assert_true(service.account.achievement_state.has("hoarder_in_training"), "500 chests unlocks Hoarder-in-Training")

func test_chests_opened_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["curious_cat"].threshold, 10)
	assert_eq(by_id["curious_cat"].counter_key, "chests_opened")
	assert_eq(by_id["curious_cat"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["chest_goblin"].threshold, 100)
	assert_eq(by_id["chest_goblin"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["hoarder_in_training"].threshold, 500)
	assert_eq(by_id["hoarder_in_training"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["hoarder_in_training"].reward_item_id, "chest_goblin_gloves")

func test_chests_opened_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("chests_opened", 500)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("curious_cat", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("chest_goblin", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("hoarder_in_training", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("chest_goblin_gloves"), "Hoarder-in-Training must grant Chest Goblin Gloves to the earning cat's bag")

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

# --- Core wiring: gold earned --------------------------------------------------

func test_gold_credited_via_kill_reward_router_increments_gold_earned_counter():
	var data := CharacterFactory.create_default("Mage")
	data.luck = 0
	var enemy_data := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var ledger := CurrencyLedger.new()
	var expected_gold := KillRewardRouter.gold_for_kill(data, enemy_data)
	KillRewardRouter.route_kill(data, enemy_data, null, "", null, null, ledger)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("gold_earned", 0)), expected_gold,
		"crediting gold via KillRewardRouter must increment gold_earned by the exact credited amount")

func test_gold_earned_counter_not_decremented_by_debit():
	var service := AchievementService.new(AccountSaveData.new())
	var ledger := CurrencyLedger.new()
	ledger.credit(500, CurrencyLedger.Currency.GOLD)
	service.increment_counter("gold_earned", 500)
	ledger.debit(300, CurrencyLedger.Currency.GOLD)
	assert_eq(int(service.account.achievement_counters.get("gold_earned", 0)), 500,
		"spending gold must not decrement the lifetime gold_earned counter")

func test_gold_earned_counter_excludes_non_gold_currency():
	var data := CharacterFactory.create_default("Mage")
	data.luck = 0
	var enemy_data := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var ledger := CurrencyLedger.new()
	ledger.credit(500, CurrencyLedger.Currency.GEM)
	var expected_gold := KillRewardRouter.gold_for_kill(data, enemy_data)
	KillRewardRouter.route_kill(data, enemy_data, null, "", null, null, ledger)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("gold_earned", 0)), expected_gold,
		"crediting a non-GOLD currency must not inflate the gold_earned counter")

# --- Content details: gold-earned tier thresholds ------------------------------

func test_gold_earned_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("gold_earned", 99)
	assert_false(service.account.achievement_state.has("spare_change"), "99 gold must not unlock Spare Change")
	service.increment_counter("gold_earned", 1)
	assert_true(service.account.achievement_state.has("spare_change"), "100 gold unlocks Spare Change")
	assert_false(service.account.achievement_state.has("comfortably_well_off"))
	service.increment_counter("gold_earned", 900)
	assert_true(service.account.achievement_state.has("comfortably_well_off"), "1,000 gold unlocks Comfortably Well-Off")
	assert_false(service.account.achievement_state.has("fat_cat"))
	service.increment_counter("gold_earned", 9000)
	assert_true(service.account.achievement_state.has("fat_cat"), "10,000 gold unlocks Fat Cat")

func test_gold_earned_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["spare_change"].threshold, 100)
	assert_eq(by_id["spare_change"].counter_key, "gold_earned")
	assert_eq(by_id["spare_change"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["comfortably_well_off"].threshold, 1000)
	assert_eq(by_id["comfortably_well_off"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["fat_cat"].threshold, 10000)
	assert_eq(by_id["fat_cat"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["fat_cat"].reward_item_id, "fat_cat_coin_purse")

func test_gold_earned_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("gold_earned", 10000)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("spare_change", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("comfortably_well_off", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("fat_cat", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("fat_cat_coin_purse"), "Fat Cat must grant Fat Cat Coin Purse to the earning cat's bag")

# --- Content details: deaths tier thresholds -----------------------------------

func test_deaths_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("deaths", 1)
	assert_true(service.account.achievement_state.has("well_that_happened"), "1 death unlocks Well, That Happened")
	assert_false(service.account.achievement_state.has("frequent_flier_respawn_edition"))
	service.increment_counter("deaths", 9)
	assert_true(service.account.achievement_state.has("frequent_flier_respawn_edition"),
		"10 deaths unlocks Frequent Flier (Respawn Edition)")
	assert_false(service.account.achievement_state.has("professional_corpse"))
	service.increment_counter("deaths", 90)
	assert_true(service.account.achievement_state.has("professional_corpse"), "100 deaths unlocks Professional Corpse")

func test_deaths_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["well_that_happened"].threshold, 1)
	assert_eq(by_id["well_that_happened"].counter_key, "deaths")
	assert_eq(by_id["well_that_happened"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["frequent_flier_respawn_edition"].threshold, 10)
	assert_eq(by_id["frequent_flier_respawn_edition"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["professional_corpse"].threshold, 100)
	assert_eq(by_id["professional_corpse"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["professional_corpse"].reward_item_id, "nine_lives_collar")

func test_deaths_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("deaths", 100)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("well_that_happened", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("frequent_flier_respawn_edition", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("professional_corpse", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("nine_lives_collar"), "Professional Corpse must grant Nine Lives Collar to the earning cat's bag")

# --- Core wiring: potion consumed via belt --------------------------------------

func _potion_caster() -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")
	c.hp = 1
	c.magic_points = 0
	return c

func test_potion_used_via_belt_increments_potions_consumed_counter():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 1)
	belt.assign(1, "health_potion")
	var ok := belt.use_slot(1, _potion_caster(), inv)
	assert_true(ok)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("potions_consumed", 0)), 1,
		"using a potion via PotionBelt.use_slot must increment the potions_consumed counter")

func test_potion_belt_failed_use_does_not_increment_potions_consumed_counter():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	var ok := belt.use_slot(1, _potion_caster(), inv)
	assert_false(ok, "an empty slot must be a no-op")
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("potions_consumed", 0)), 0,
		"a failed potion use (empty slot) must not increment potions_consumed")

# --- Content details: potions-consumed tier thresholds --------------------------

func test_potions_consumed_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("potions_consumed", 9)
	assert_false(service.account.achievement_state.has("just_in_case"), "9 potions must not unlock Just in Case")
	service.increment_counter("potions_consumed", 1)
	assert_true(service.account.achievement_state.has("just_in_case"), "10 potions unlocks Just in Case")
	assert_false(service.account.achievement_state.has("bottoms_up"))
	service.increment_counter("potions_consumed", 40)
	assert_true(service.account.achievement_state.has("bottoms_up"), "50 potions unlocks Bottoms Up")
	assert_false(service.account.achievement_state.has("potion_sommelier"))
	service.increment_counter("potions_consumed", 150)
	assert_true(service.account.achievement_state.has("potion_sommelier"), "200 potions unlocks Potion Sommelier")

func test_potions_consumed_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["just_in_case"].threshold, 10)
	assert_eq(by_id["just_in_case"].counter_key, "potions_consumed")
	assert_eq(by_id["just_in_case"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["bottoms_up"].threshold, 50)
	assert_eq(by_id["bottoms_up"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["potion_sommelier"].threshold, 200)
	assert_eq(by_id["potion_sommelier"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["potion_sommelier"].reward_item_id, "alchemists_flask")

func test_potions_consumed_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("potions_consumed", 200)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("just_in_case", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("bottoms_up", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("potion_sommelier", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("alchemists_flask"), "Potion Sommelier must grant Alchemist's Flask to the earning cat's bag")

# --- Core wiring: drinks (beer + ale) -------------------------------------------

func test_buying_beer_increments_drinks_counter():
	var bartender: Bartender = load("res://scenes/bartender.tscn").instantiate()
	add_child_autofree(bartender)
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var character := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	bartender.setup_economy(ledger, character)
	bartender._handle_effect("buy_beer")
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 1,
		"buying a beer must increment the shared drinks counter")

func test_unaffordable_beer_does_not_increment_drinks_counter():
	var bartender: Bartender = load("res://scenes/bartender.tscn").instantiate()
	add_child_autofree(bartender)
	var ledger := CurrencyLedger.new()
	var character := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	bartender.setup_economy(ledger, character)
	bartender._handle_effect("buy_beer")
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 0,
		"an unaffordable beer must not increment the drinks counter")

func test_ale_pickup_increments_drinks_counter():
	var pickup := PowerUpPickup.new()
	pickup.power_up_type = PowerUpEffect.TYPE_ALE
	add_child_autofree(pickup)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	add_child_autofree(p)
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 1,
		"picking up an ale power-up must increment the shared drinks counter")

func test_non_ale_pickup_does_not_increment_drinks_counter():
	var pickup := PowerUpPickup.new()
	pickup.power_up_type = PowerUpEffect.TYPE_CATNIP
	add_child_autofree(pickup)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	add_child_autofree(p)
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 0,
		"picking up a non-ale power-up must not increment the drinks counter")

func test_beer_and_ale_share_the_same_drinks_counter():
	var bartender: Bartender = load("res://scenes/bartender.tscn").instantiate()
	add_child_autofree(bartender)
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var character := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	bartender.setup_economy(ledger, character)
	bartender._handle_effect("buy_beer")
	bartender._handle_effect("buy_beer")
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	add_child_autofree(p)
	for i in range(3):
		var pickup := PowerUpPickup.new()
		pickup.power_up_type = PowerUpEffect.TYPE_ALE
		add_child_autofree(pickup)
		pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 5,
		"2 beers + 3 ale pickups must combine into one 5-drink total")

# --- Content details: drinks tier thresholds --------------------------------------

func test_drinks_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("drinks", 4)
	assert_false(service.account.achievement_state.has("happy_hour"), "4 drinks must not unlock Happy Hour")
	service.increment_counter("drinks", 1)
	assert_true(service.account.achievement_state.has("happy_hour"), "5 drinks unlocks Happy Hour")
	assert_false(service.account.achievement_state.has("bar_regular"))
	service.increment_counter("drinks", 20)
	assert_true(service.account.achievement_state.has("bar_regular"), "25 drinks unlocks Bar Regular")
	assert_false(service.account.achievement_state.has("liver_of_steel"))
	service.increment_counter("drinks", 75)
	assert_true(service.account.achievement_state.has("liver_of_steel"), "100 drinks unlocks Liver of Steel")

func test_drinks_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["happy_hour"].threshold, 5)
	assert_eq(by_id["happy_hour"].counter_key, "drinks")
	assert_eq(by_id["happy_hour"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["bar_regular"].threshold, 25)
	assert_eq(by_id["bar_regular"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["liver_of_steel"].threshold, 100)
	assert_eq(by_id["liver_of_steel"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["liver_of_steel"].reward_item_id, "bar_regulars_mug")

func test_drinks_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("drinks", 100)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("happy_hour", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("bar_regular", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("liver_of_steel", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("bar_regulars_mug"), "Liver of Steel must grant Bar Regular's Mug to the earning cat's bag")

# --- Core wiring: catnip_snarfed -------------------------------------------

func test_catnip_pickup_increments_catnip_snarfed_counter():
	var pickup := PowerUpPickup.new()
	pickup.power_up_type = PowerUpEffect.TYPE_CATNIP
	add_child_autofree(pickup)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	add_child_autofree(p)
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("catnip_snarfed", 0)), 1,
		"picking up a catnip power-up must increment the catnip_snarfed counter")

func test_non_catnip_pickup_does_not_increment_catnip_snarfed_counter():
	var pickup := PowerUpPickup.new()
	pickup.power_up_type = PowerUpEffect.TYPE_ALE
	add_child_autofree(pickup)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	add_child_autofree(p)
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("catnip_snarfed", 0)), 0,
		"picking up a non-catnip power-up must not increment the catnip_snarfed counter")

# --- Content details: catnip_snarfed tier thresholds --------------------------------------

func test_catnip_snarfed_tiers_unlock_at_correct_counts_using_real_catalog():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.increment_counter("catnip_snarfed", 4)
	assert_false(service.account.achievement_state.has("sniff_test"), "4 catnip pickups must not unlock Sniff Test")
	service.increment_counter("catnip_snarfed", 1)
	assert_true(service.account.achievement_state.has("sniff_test"), "5 catnip pickups unlocks Sniff Test")
	assert_false(service.account.achievement_state.has("catnip_enthusiast"))
	service.increment_counter("catnip_snarfed", 20)
	assert_true(service.account.achievement_state.has("catnip_enthusiast"), "25 catnip pickups unlocks Catnip Enthusiast")
	assert_false(service.account.achievement_state.has("certified_space_cat"))
	service.increment_counter("catnip_snarfed", 75)
	assert_true(service.account.achievement_state.has("certified_space_cat"), "100 catnip pickups unlocks Certified Space Cat")

func test_catnip_snarfed_tiers_have_correct_thresholds_and_rewards():
	var by_id := {}
	for d in AchievementCatalog.all():
		by_id[d.id] = d
	assert_eq(by_id["sniff_test"].threshold, 5)
	assert_eq(by_id["sniff_test"].counter_key, "catnip_snarfed")
	assert_eq(by_id["sniff_test"].reward_type, AchievementDefinition.RewardType.GOLD)
	assert_eq(by_id["catnip_enthusiast"].threshold, 25)
	assert_eq(by_id["catnip_enthusiast"].reward_type, AchievementDefinition.RewardType.POTION)
	assert_eq(by_id["certified_space_cat"].threshold, 100)
	assert_eq(by_id["certified_space_cat"].reward_type, AchievementDefinition.RewardType.ITEM)
	assert_eq(by_id["certified_space_cat"].reward_item_id, "catnip_crown")

func test_catnip_snarfed_tier_rewards_are_claimable():
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	service.active_slot = "wizard_kitten"
	service.increment_counter("catnip_snarfed", 100)
	var ledger := CurrencyLedger.new()
	var claimed_gold := service.claim("sniff_test", ledger)
	assert_not_null(claimed_gold)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), claimed_gold.reward_amount)
	var potions := ConsumableInventory.new()
	var claimed_potion := service.claim("catnip_enthusiast", null, potions)
	assert_not_null(claimed_potion)
	assert_eq(potions.count_of(claimed_potion.reward_potion_id), claimed_potion.reward_amount)
	var items := ItemInventory.new()
	var claimed_item := service.claim("certified_space_cat", null, null, null, items)
	assert_not_null(claimed_item)
	var bag_ids: Array = []
	for item in items.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("catnip_crown"), "Certified Space Cat must grant Catnip Crown to the earning cat's bag")
