extends GutTest

# Slice 6 of the monetization pivot (PRD #26, issue #32). PurchaseGrantHandler
# is the dispatch layer between BillingManager.purchase_succeeded and the
# concrete grant actions (ClassTierUpgrade.upgrade / CosmeticInventory.grant /
# class-unlock stub). Stateless static surface so the rules can be exercised
# without booting the autoload — the GameState integration block below pins
# the signal wiring end-to-end.

const TMP_SAVE_PATH := "user://save.json"

func _cleanup_save() -> void:
	if FileAccess.file_exists(TMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE_PATH))

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
	_cleanup_save()

# --- Issue tests (acceptance criteria) --------------------------------------

func test_class_upgrade_on_matching_class():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE, c, inv)
	assert_true(ok, "handle returns true on successful upgrade")
	assert_eq(c.character_class, int(CharacterData.CharacterClass.ARCHMAGE),
		"mage promoted to archmage")

func test_class_upgrade_wrong_class_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE, c, inv)
	assert_false(ok, "wrong-class upgrade is no-op")
	assert_eq(c.character_class, int(CharacterData.CharacterClass.NINJA),
		"ninja stays ninja")

func test_cosmetic_pack_grant():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(PurchaseRegistry.COSMETIC_COAT_PACK, c, inv)
	assert_true(ok, "cosmetic grant returns true on first grant")
	assert_true(inv.has_pack(PurchaseRegistry.COSMETIC_COAT_PACK),
		"pack appears in inventory after grant")

func test_unknown_product_returns_false():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := CosmeticInventory.new()
	assert_false(PurchaseGrantHandler.handle("fake_product_xyz", c, inv))

func test_null_character_is_safe():
	# Class-upgrade path must null-check before reading character_class.
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE, null, inv)
	assert_false(ok)

# --- Coverage extras --------------------------------------------------------

func test_cosmetic_pack_replay_returns_false():
	# Restore-from-server replay path: BillingManager.queryPurchases re-emits
	# purchase_succeeded for already-owned items. Second grant must be a
	# semantic no-op (returns false) so the GameState handler skips the
	# redundant SaveManager.save and the call site can branch off the
	# return value if it ever wants to fire "fresh-grant VFX" vs "silent".
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := CosmeticInventory.new()
	assert_true(PurchaseGrantHandler.handle(PurchaseRegistry.COSMETIC_COAT_PACK, c, inv))
	assert_false(PurchaseGrantHandler.handle(PurchaseRegistry.COSMETIC_COAT_PACK, c, inv),
		"replay returns false; inventory.grant idempotent")
	assert_eq(inv.owned_pack_ids.size(), 1, "no duplicate entry")

func test_class_upgrade_without_tier_map_entry_is_noop():
	# Thief -> Master Thief / Ninja -> Shadow Ninja are in PurchaseRegistry
	# but NOT yet in ClassTierUpgrade.TIER_MAP. handle() must surface that
	# as no-op (false) rather than mutating the character; the shop UI can
	# then surface a "coming soon" path.
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.UPGRADE_THIEF_MASTER_THIEF, c, inv)
	assert_false(ok, "no TIER_MAP entry -> no grant")
	assert_eq(c.character_class, int(CharacterData.CharacterClass.THIEF))

func test_class_unlock_returns_true_stub():
	# Class-unlock products are PRD-listed but UnlockRegistry isn't wired to
	# IAP yet (it's earnable today). Stub returns true so BillingManager's
	# acknowledgement path doesn't loop and so the grant handler counts it
	# as "applied" for save-trigger purposes.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, inv)
	assert_true(ok, "class-unlock stub returns true")

func test_null_cosmetic_inventory_safe_on_cosmetic_grant():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.COSMETIC_COAT_PACK, c, null)
	assert_false(ok, "missing inventory -> no grant, no crash")

func test_archmage_buying_mage_upgrade_is_noop():
	# An Archmage character already passed through this upgrade. Re-purchasing
	# (e.g. restore-purchases) must not re-upgrade or double-promote.
	# Defensively this is also "wrong-class" since ARCHMAGE != MAGE.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.character_class = CharacterData.CharacterClass.ARCHMAGE
	var inv := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE, c, inv)
	assert_false(ok)
	assert_eq(c.character_class, int(CharacterData.CharacterClass.ARCHMAGE))

# --- GameState signal-wiring integration ------------------------------------

func test_purchase_succeeded_signal_upgrades_current_character():
	# Acceptance criterion: GameState listens to BillingManager.purchase_succeeded
	# and routes through the grant handler so the active character is mutated.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE)
	# Signal callbacks fire synchronously in Godot — no await needed.
	assert_eq(gs.current_character.character_class,
		int(CharacterData.CharacterClass.ARCHMAGE),
		"current_character promoted to Archmage")

func test_purchase_succeeded_signal_persists_save():
	# Acceptance criterion: "After a successful grant, GameState calls
	# SaveManager.save so the grant survives a restart." Verify by reading
	# the written file back and confirming the upgraded class made it.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE)
	assert_true(FileAccess.file_exists(TMP_SAVE_PATH),
		"save file written after grant")
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_class, int(CharacterData.CharacterClass.ARCHMAGE),
		"upgraded class persisted to disk")

func test_purchase_succeeded_persists_cosmetic_grant():
	# SaveManager.save must thread cosmetic_inventory through into
	# KittenSaveData.cosmetic_packs (slice 4 left this for slice 6).
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.COSMETIC_COAT_PACK)
	assert_true(gs.cosmetic_inventory.has_pack(PurchaseRegistry.COSMETIC_COAT_PACK),
		"inventory updated in-memory")
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_true(loaded.cosmetic_packs.has(PurchaseRegistry.COSMETIC_COAT_PACK),
		"cosmetic pack persisted via SaveManager.save")

func test_purchase_succeeded_unknown_product_no_save():
	# No grant => no save. Otherwise every spurious purchase_succeeded would
	# clobber the on-disk file with an unchanged character — harmless but
	# unnecessary IO, and would make "did the grant apply?" untestable.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))
	bm.purchase_succeeded.emit("totally_unknown_product")
	assert_false(FileAccess.file_exists(TMP_SAVE_PATH),
		"no save on unknown product")
