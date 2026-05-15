extends GutTest

# Tracer-bullet slice 7 for PRD #53 (issue #69). Extends PurchaseGrantHandler
# with two new grant routes — Gem bundle (consumable, credits CurrencyLedger)
# and skill unlock (non-consumable, populates SkillInventory) — plus a new
# replay guard on CurrencyLedger so a re-fired bundle purchase doesn't
# double-credit Gems.

const TMP_SAVE_PATH := "user://save.json"

func _cleanup_save() -> void:
	if FileAccess.file_exists(TMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE_PATH))

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
	_cleanup_save()

# --- Gem bundle dispatch ----------------------------------------------------

func test_gem_bundle_starter_credits_100_gems():
	var ledger := CurrencyLedger.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_STARTER, null, null, null, ledger)
	assert_true(ok, "starter bundle grant returns true")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 100)

func test_all_four_bundle_amounts():
	var cases := [
		[PurchaseRegistry.GEM_BUNDLE_STARTER, 100],
		[PurchaseRegistry.GEM_BUNDLE_EXPLORER, 600],
		[PurchaseRegistry.GEM_BUNDLE_ADVENTURER, 1400],
		[PurchaseRegistry.GEM_BUNDLE_HERO, 3000],
	]
	for c in cases:
		var ledger := CurrencyLedger.new()
		PurchaseGrantHandler.handle(c[0], null, null, null, ledger)
		assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), c[1],
			"bundle %s credits %d Gems" % [c[0], c[1]])

func test_gem_bundle_idempotency():
	# Replay-on-startup defense: BillingManager re-fires purchase_succeeded
	# for unconsumed tokens. Second call returns false; balance unchanged.
	var ledger := CurrencyLedger.new()
	assert_true(PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_STARTER, null, null, null, ledger))
	var second := PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_STARTER, null, null, null, ledger)
	assert_false(second, "replay returns false")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 100,
		"no double-credit")

func test_gem_bundle_no_ledger_is_noop():
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_STARTER, null, null, null, null)
	assert_false(ok)

func test_gem_bundle_grant_type():
	assert_eq(PurchaseRegistry.grant_type_for(PurchaseRegistry.GEM_BUNDLE_STARTER),
		PurchaseRegistry.GRANT_GEM_BUNDLE)

func test_gem_amount_for_non_bundle_is_zero():
	# Non-bundle product ids return 0 so a future mis-routing can't accidentally
	# mint Gems.
	assert_eq(PurchaseRegistry.gem_amount_for(
		PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT), 0)
	assert_eq(PurchaseRegistry.gem_amount_for("unknown_product"), 0)

func test_distinct_bundles_each_credit_once():
	# Replay guard is per-product_id, not blanket "no second bundle ever."
	var ledger := CurrencyLedger.new()
	PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_STARTER, null, null, null, ledger)
	PurchaseGrantHandler.handle(
		PurchaseRegistry.GEM_BUNDLE_EXPLORER, null, null, null, ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 700,
		"distinct bundles stack (100 + 600)")

# --- Skill unlock dispatch --------------------------------------------------

func test_skill_unlock_fireball():
	var ledger := CurrencyLedger.new()
	var inv := SkillInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL, null, null, null, ledger, inv)
	assert_true(ok, "first grant returns true")
	assert_true(inv.has_skill("fireball"))

func test_skill_unlock_idempotent():
	var ledger := CurrencyLedger.new()
	var inv := SkillInventory.new()
	PurchaseGrantHandler.handle(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL, null, null, null, ledger, inv)
	var second := PurchaseGrantHandler.handle(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL, null, null, null, ledger, inv)
	assert_false(second, "second grant returns false")
	assert_eq(inv.owned_skill_ids.size(), 1, "no duplicate entry")

func test_skill_unlock_without_inventory_is_noop():
	var ledger := CurrencyLedger.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL, null, null, null, ledger, null)
	assert_false(ok)

func test_skill_unlock_grant_type():
	assert_eq(PurchaseRegistry.grant_type_for(PurchaseRegistry.SKILL_UNLOCK_FIREBALL),
		PurchaseRegistry.GRANT_SKILL_UNLOCK)

func test_skill_id_for_unlock():
	assert_eq(PurchaseRegistry.skill_id_for_unlock(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL), "fireball")
	assert_eq(PurchaseRegistry.skill_id_for_unlock(
		PurchaseRegistry.SKILL_UNLOCK_SHADOWSTEP), "shadowstep")
	assert_eq(PurchaseRegistry.skill_id_for_unlock(
		PurchaseRegistry.SKILL_UNLOCK_SMOKE_BOMB), "smoke_bomb")
	assert_eq(PurchaseRegistry.skill_id_for_unlock("unknown_product"), "")

# --- SkillInventory primitives ---------------------------------------------

func test_skill_inventory_grant_idempotent():
	var inv := SkillInventory.new()
	assert_true(inv.grant("fireball"))
	assert_false(inv.grant("fireball"))
	assert_true(inv.has_skill("fireball"))

func test_skill_inventory_grant_empty_id_rejected():
	var inv := SkillInventory.new()
	assert_false(inv.grant(""))

func test_skill_inventory_round_trip():
	var inv := SkillInventory.new()
	inv.grant("fireball")
	inv.grant("shadowstep")
	var d := inv.to_dict()
	var restored: SkillInventory = SkillInventory.from_dict(d)
	assert_true(restored.has_skill("fireball"))
	assert_true(restored.has_skill("shadowstep"))
	assert_eq(restored.owned_skill_ids.size(), 2)

func test_skill_inventory_round_trip_via_save():
	# SkillInventory survives the SaveManager.save -> load cycle through
	# KittenSaveData.skill_unlocks. Same shape as cosmetic_packs.
	_cleanup_save()
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var inv := SkillInventory.new()
	inv.grant("fireball")
	inv.grant("shadowstep")
	var err := SaveManager.save(c, TMP_SAVE_PATH, null, null, null, null, null, {}, null, inv)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_true(loaded.skill_unlocks.has("fireball"))
	assert_true(loaded.skill_unlocks.has("shadowstep"))
	var restored: SkillInventory = loaded.to_skill_inventory()
	assert_true(restored.has_skill("fireball"))

func test_legacy_save_defaults_to_empty_skill_unlocks():
	var legacy := KittenSaveData.from_dict({"character_name": "Old"})
	assert_eq(legacy.skill_unlocks.size(), 0)
	var inv: SkillInventory = legacy.to_skill_inventory()
	assert_eq(inv.owned_skill_ids.size(), 0)

# --- GameState integration --------------------------------------------------

func test_gamestate_holds_non_null_skill_inventory():
	var gs := get_node("/root/GameState")
	assert_not_null(gs.skill_inventory)

func test_purchase_succeeded_signal_credits_gem_bundle():
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_eq(gs.currency_ledger.balance(CurrencyLedger.Currency.GEM), 100,
		"signal credits Gems")
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.gem_balance, 100, "balance persisted")

func test_purchase_succeeded_signal_grants_skill_unlock():
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.SKILL_UNLOCK_FIREBALL)
	assert_true(gs.skill_inventory.has_skill("fireball"))
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_true(loaded.skill_unlocks.has("fireball"))
