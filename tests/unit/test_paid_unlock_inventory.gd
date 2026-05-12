extends GutTest

# Slice: paid class-unlock path (PRD #26 Tier 3 — "Class Unlock Shortcut").
# PaidUnlockInventory is the sibling-to-CosmeticInventory bucket of class id
# strings purchased via non-consumable IAP. UnlockRegistry.is_unlocked
# consults it as an OR'd path next to the gameplay condition gates, so a
# paid unlock bypasses the meta-progression threshold without removing the
# earnable path (PRD's "earnable through gameplay OR purchased").

# --- PaidUnlockInventory primitives ----------------------------------------

func test_grant_then_has_unlock():
	var inv := PaidUnlockInventory.new()
	assert_true(inv.grant("archmage"))
	assert_true(inv.has_unlock("archmage"))

func test_grant_is_idempotent():
	var inv := PaidUnlockInventory.new()
	assert_true(inv.grant("archmage"))
	assert_false(inv.grant("archmage"), "second grant returns false")
	assert_eq(inv.owned_class_ids.size(), 1, "no duplicate entries")

func test_has_unlock_false_for_unowned():
	var inv := PaidUnlockInventory.new()
	assert_false(inv.has_unlock("archmage"))

func test_grant_normalizes_case():
	# Class id keys are lower-cased on write so a case-mismatched product id
	# parse (e.g. "Archmage") doesn't produce a parallel "Archmage" entry next
	# to "archmage". Matches UnlockRegistry's case-insensitive lookup shape.
	var inv := PaidUnlockInventory.new()
	assert_true(inv.grant("Archmage"))
	assert_true(inv.has_unlock("archmage"), "lookup case-insensitive")
	assert_false(inv.grant("ARCHMAGE"), "case-folded duplicate rejected")
	assert_eq(inv.owned_class_ids.size(), 1)

func test_empty_class_id_rejected():
	# Empty id is a defensive skip — same shape as CosmeticInventory's
	# implicit duplicate-empty guard. A corrupted payload can't grow the
	# inventory with no key.
	var inv := PaidUnlockInventory.new()
	assert_false(inv.grant(""))
	assert_eq(inv.owned_class_ids.size(), 0)

func test_dict_round_trip():
	var inv := PaidUnlockInventory.new()
	inv.grant("archmage")
	inv.grant("master_thief")
	var restored := PaidUnlockInventory.from_dict(inv.to_dict())
	assert_true(restored.has_unlock("archmage"))
	assert_true(restored.has_unlock("master_thief"))
	assert_eq(restored.owned_class_ids.size(), 2)

func test_from_dict_handles_missing_key():
	# Legacy save blob without paid unlocks hydrates to an empty inventory
	# rather than crashing on the missing field.
	var restored := PaidUnlockInventory.from_dict({})
	assert_eq(restored.owned_class_ids.size(), 0)

func test_from_dict_rejects_non_array_field():
	# Defense-in-depth: corrupted JSON falls back to empty rather than
	# carrying garbage through has_unlock.
	var restored := PaidUnlockInventory.from_dict({"owned_class_ids": "not-an-array"})
	assert_eq(restored.owned_class_ids.size(), 0)

func test_from_dict_skips_empty_and_dedupes():
	# Corrupted payload with empty / duplicate / mixed-case ids — hydrate the
	# defensive clean set so the loaded inventory matches the write-time
	# contract (lowercase, deduped, no empties).
	var restored := PaidUnlockInventory.from_dict({
		"owned_class_ids": ["archmage", "", "ARCHMAGE", "ninja"],
	})
	assert_eq(restored.owned_class_ids.size(), 2)
	assert_true(restored.has_unlock("archmage"))
	assert_true(restored.has_unlock("ninja"))

func test_to_dict_clones_array():
	# Mutating the returned dict's array must not stealth-mutate the
	# inventory. Matters when a single dict feeds multiple from_dict /
	# round-trip merge paths.
	var inv := PaidUnlockInventory.new()
	inv.grant("archmage")
	var d := inv.to_dict()
	d["owned_class_ids"].append("ninja")
	assert_false(inv.has_unlock("ninja"), "inventory unaffected")

# --- KittenSaveData wiring --------------------------------------------------

func test_kitten_save_data_to_dict_emits_paid_class_unlocks():
	var sd := KittenSaveData.new()
	sd.paid_class_unlocks = ["archmage"]
	var d := sd.to_dict()
	assert_true(d.has("paid_class_unlocks"))
	assert_eq(d["paid_class_unlocks"], ["archmage"])

func test_kitten_save_data_paid_class_unlocks_round_trips():
	var sd := KittenSaveData.new()
	sd.paid_class_unlocks = ["archmage", "master_thief"]
	var restored := KittenSaveData.from_dict(sd.to_dict())
	assert_eq(restored.paid_class_unlocks.size(), 2)
	assert_true(restored.paid_class_unlocks.has("archmage"))
	assert_true(restored.paid_class_unlocks.has("master_thief"))

func test_kitten_save_data_from_character_captures_paid_unlocks():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	var inv := PaidUnlockInventory.new()
	inv.grant("archmage")
	inv.grant("ninja")
	var sd := KittenSaveData.from_character(c, null, null, null, null, inv)
	assert_eq(sd.paid_class_unlocks.size(), 2)
	assert_true(sd.paid_class_unlocks.has("archmage"))
	assert_true(sd.paid_class_unlocks.has("ninja"))

func test_kitten_save_data_from_character_null_unlocks_keeps_default():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var sd := KittenSaveData.from_character(c, null, null, null, null, null)
	assert_eq(sd.paid_class_unlocks.size(), 0)

func test_kitten_save_data_to_paid_unlock_inventory():
	var sd := KittenSaveData.new()
	sd.paid_class_unlocks = ["archmage"]
	var inv := sd.to_paid_unlock_inventory()
	assert_true(inv.has_unlock("archmage"))
	assert_false(inv.has_unlock("ninja"))

func test_legacy_save_no_paid_unlocks_defaults_empty():
	# Saves predating this field hydrate to an empty inventory.
	var legacy := {
		"character_name": "Old",
		"character_class": int(CharacterData.CharacterClass.MAGE),
		"level": 1, "xp": 0,
		"hp": 8, "max_hp": 8,
		"attack": 2, "defense": 0, "speed": 50.0,
		"skill_points": 0,
	}
	var sd := KittenSaveData.from_dict(legacy)
	var inv := sd.to_paid_unlock_inventory()
	assert_eq(inv.owned_class_ids.size(), 0)

# --- UnlockRegistry consultation -------------------------------------------

func test_is_unlocked_paid_bypasses_threshold():
	# AC: a paid unlock makes is_unlocked return true even with a fresh
	# tracker that doesn't meet the gameplay condition. Pins user story 42
	# ("Purchase a class unlock to immediately access a class I haven't
	# earned yet").
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	assert_false(registry.is_unlocked("archmage", tracker, paid),
		"locked before purchase (no condition met, no paid entry)")
	paid.grant("archmage")
	assert_true(registry.is_unlocked("archmage", tracker, paid),
		"paid grant unlocks regardless of tracker state")

func test_is_unlocked_paid_works_with_null_tracker():
	# Pre-meta-progression / fresh-install / corrupt-save: paid path still
	# fires without a tracker. Defensive against a startup race where
	# meta_tracker hasn't loaded yet.
	var registry := UnlockRegistry.make_default()
	var paid := PaidUnlockInventory.new()
	paid.grant("archmage")
	assert_true(registry.is_unlocked("archmage", null, paid),
		"paid grant unlocks without tracker")

func test_is_unlocked_gameplay_path_still_works():
	# Earnable path coexists with paid path — PRD's "earnable through
	# gameplay OR purchased." A player who hits the gameplay condition
	# without buying still gets the unlock.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	tracker.record_level_reached("mage", 5)
	var paid := PaidUnlockInventory.new()
	assert_true(registry.is_unlocked("archmage", tracker, paid),
		"gameplay condition still unlocks")
	# And without paid_unlocks at all.
	assert_true(registry.is_unlocked("archmage", tracker),
		"back-compat: optional paid arg defaults to null")

func test_is_unlocked_paid_does_not_bleed_to_unrelated_id():
	# Paid grant of "archmage" doesn't unlock "ninja". Per-id isolation.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	paid.grant("archmage")
	assert_false(registry.is_unlocked("ninja", tracker, paid))

func test_is_unlocked_paid_case_insensitive_lookup():
	# Caller passes "Archmage" -> matches stored "archmage". Same case-fold
	# rule as starter-class lookup.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	paid.grant("archmage")
	assert_true(registry.is_unlocked("Archmage", tracker, paid))

func test_check_all_surfaces_paid_unlocks():
	# check_all consults paid_unlocks too — UI's "what's currently
	# unlocked" projection reflects paid grants.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	paid.grant("ninja")
	var unlocked := registry.check_all(tracker, paid)
	assert_true(unlocked.has("ninja"), "ninja surfaces via paid path")
	assert_false(unlocked.has("archmage"), "archmage still locked")

func test_newly_unlocked_surfaces_paid_grant_transition():
	# A purchase between two snapshots surfaces in newly_unlocked so the
	# UI can fire its "new class available!" toast on the paid path too.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	var prev := registry.check_all(tracker, paid)
	paid.grant("archmage")
	var new_ids := registry.newly_unlocked(prev, tracker, paid)
	assert_true(new_ids.has("archmage"))

# --- PurchaseRegistry parsing ----------------------------------------------

func test_class_id_for_unlock_archmage():
	assert_eq(
		PurchaseRegistry.class_id_for_unlock(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE),
		"archmage")

func test_class_id_for_unlock_cosmetic_returns_empty():
	# Non-unlock products return empty so PurchaseGrantHandler can branch
	# off the empty sentinel without special-casing the lookup.
	assert_eq(
		PurchaseRegistry.class_id_for_unlock(PurchaseRegistry.COSMETIC_COAT_PACK),
		"")

func test_class_id_for_unlock_unknown_returns_empty():
	assert_eq(PurchaseRegistry.class_id_for_unlock("totally_unknown"), "")

# --- PurchaseGrantHandler dispatch -----------------------------------------

func test_handle_class_unlock_grants_paid_entry():
	# AC: BillingManager fires purchase_succeeded(CLASS_UNLOCK_ARCHMAGE) ->
	# PurchaseGrantHandler routes to PaidUnlockInventory.grant("archmage") ->
	# inventory carries the entry.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var cos := CosmeticInventory.new()
	var paid := PaidUnlockInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, cos, paid)
	assert_true(ok, "handle returns true on first grant")
	assert_true(paid.has_unlock("archmage"),
		"paid inventory now owns the unlock")

func test_handle_class_unlock_replay_returns_false():
	# Restore-from-server replay path: BillingManager.queryPurchases re-emits
	# purchase_succeeded for already-owned items. Second grant must return
	# false so GameState skips the redundant SaveManager.save.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var cos := CosmeticInventory.new()
	var paid := PaidUnlockInventory.new()
	assert_true(PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, cos, paid))
	assert_false(PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, cos, paid),
		"replay returns false; PaidUnlockInventory.grant idempotent")
	assert_eq(paid.owned_class_ids.size(), 1)

func test_handle_class_unlock_null_paid_inventory_safe():
	# Back-compat: legacy call sites that don't pass paid_unlocks fall
	# through to a "no grant landed" no-op rather than crashing. Same shape
	# as null cosmetic_inventory for cosmetic-pack grants.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var cos := CosmeticInventory.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, cos)
	assert_false(ok)

func test_handle_class_unlock_does_not_mutate_character():
	# Class-unlock is a roster gate, not a stat upgrade — the active
	# character is unchanged. (Vs class_upgrade which DOES mutate.)
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var cos := CosmeticInventory.new()
	var paid := PaidUnlockInventory.new()
	PurchaseGrantHandler.handle(
		PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE, c, cos, paid)
	assert_eq(c.character_class, int(CharacterData.CharacterClass.MAGE),
		"character stays as Mage after Archmage unlock purchase")

# --- GameState signal-wiring integration -----------------------------------

const TMP_SAVE_PATH := "user://save.json"

func _cleanup_save() -> void:
	if FileAccess.file_exists(TMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE_PATH))

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
	_cleanup_save()

func test_game_state_paid_unlocks_defaults_non_null():
	var gs := get_node("/root/GameState")
	assert_not_null(gs.paid_unlocks, "always non-null on autoload init")
	assert_eq(gs.paid_unlocks.owned_class_ids.size(), 0,
		"fresh inventory starts empty")

func test_game_state_apply_merged_save_hydrates_paid_unlocks():
	var gs := get_node("/root/GameState")
	var save := KittenSaveData.new()
	save.paid_class_unlocks = ["archmage"]
	gs.apply_merged_save(save)
	assert_true(gs.paid_unlocks.has_unlock("archmage"))
	assert_false(gs.paid_unlocks.has_unlock("ninja"))

func test_game_state_clear_drops_paid_unlocks():
	# clear() must reset the inventory so a logout / character-reset doesn't
	# leak the prior account's purchases into a fresh save.
	var gs := get_node("/root/GameState")
	gs.paid_unlocks.grant("archmage")
	gs.clear()
	assert_not_null(gs.paid_unlocks, "still non-null after clear")
	assert_eq(gs.paid_unlocks.owned_class_ids.size(), 0,
		"prior grants dropped")

func test_purchase_succeeded_signal_grants_paid_unlock():
	# AC end-to-end: BillingManager.purchase_succeeded(CLASS_UNLOCK_ARCHMAGE)
	# -> GameState._on_purchase_succeeded -> PurchaseGrantHandler -> paid
	# inventory now owns archmage.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE)
	assert_true(gs.paid_unlocks.has_unlock("archmage"),
		"inventory updated in-memory via signal")

func test_purchase_succeeded_persists_paid_unlock_to_save():
	# Persistence AC: the grant survives a restart. Verified by reading
	# the written file back through KittenSaveData.from_dict.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers"))
	bm.purchase_succeeded.emit(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE)
	assert_true(FileAccess.file_exists(TMP_SAVE_PATH))
	var loaded := SaveManager.load(TMP_SAVE_PATH)
	assert_not_null(loaded)
	assert_true(loaded.paid_class_unlocks.has("archmage"),
		"paid unlock persisted via SaveManager.save")

func test_purchase_succeeded_replay_no_redundant_save():
	# Replay path: second emit returns false from handle() so no save
	# rewrite happens. Same shape as the cosmetic-replay contract.
	_cleanup_save()
	var gs := get_node("/root/GameState")
	var bm := get_node("/root/BillingManager")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))
	bm.purchase_succeeded.emit(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE)
	# Delete the save file the first emit wrote, then replay. If the second
	# emit returns false (replay handled), no new file should be written.
	_cleanup_save()
	bm.purchase_succeeded.emit(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE)
	assert_false(FileAccess.file_exists(TMP_SAVE_PATH),
		"no save on replay grant")

func test_unlock_registry_reads_paid_unlocks_from_game_state():
	# Integration: the unlock-gate call site (character_creation.gd) now
	# threads GameState.paid_unlocks into is_unlocked. Verify the autoload
	# wiring matches the call-site shape.
	var gs := get_node("/root/GameState")
	gs.paid_unlocks.grant("ninja")
	var unlocked: bool = gs.unlock_registry.is_unlocked(
		"ninja", gs.meta_tracker, gs.paid_unlocks)
	assert_true(unlocked,
		"ninja unlocked via paid path against autoload state")
