extends GutTest

# --- Issue tests (acceptance criteria) --------------------------------------

func test_grant_then_has_pack():
	var inv := CosmeticInventory.new()
	assert_true(inv.grant("cosmetic_coat_pack"))
	assert_true(inv.has_pack("cosmetic_coat_pack"))

func test_grant_is_idempotent():
	var inv := CosmeticInventory.new()
	assert_true(inv.grant("cosmetic_coat_pack"))
	assert_false(inv.grant("cosmetic_coat_pack"), "second grant returns false")
	assert_eq(inv.owned_pack_ids.size(), 1, "no duplicate entries")

func test_has_pack_false_for_unowned():
	var inv := CosmeticInventory.new()
	assert_false(inv.has_pack("cosmetic_coat_pack"))

func test_dict_round_trip():
	var inv := CosmeticInventory.new()
	inv.grant("cosmetic_coat_pack")
	inv.grant("cosmetic_spell_effects")
	var restored := CosmeticInventory.from_dict(inv.to_dict())
	assert_true(restored.has_pack("cosmetic_coat_pack"))
	assert_true(restored.has_pack("cosmetic_spell_effects"))
	assert_eq(restored.owned_pack_ids.size(), 2)

func test_legacy_save_no_cosmetic_packs_defaults_empty():
	var legacy := {
		"character_name": "Old",
		"character_class": int(CharacterData.CharacterClass.MAGE),
		"level": 1, "xp": 0,
		"hp": 8, "max_hp": 8,
		"attack": 2, "defense": 0, "speed": 50.0,
		"skill_points": 0,
	}
	var sd := KittenSaveData.from_dict(legacy)
	var inv := sd.to_cosmetic_inventory()
	assert_eq(inv.owned_pack_ids.size(), 0)

# --- Coverage extras --------------------------------------------------------

func test_fresh_inventory_owns_nothing():
	var inv := CosmeticInventory.new()
	assert_eq(inv.owned_pack_ids.size(), 0)

func test_from_dict_handles_missing_key():
	# A dict that doesn't carry the field at all (legacy CosmeticInventory
	# blob, or a malformed payload) hydrates to an empty inventory rather
	# than crashing.
	var restored := CosmeticInventory.from_dict({})
	assert_eq(restored.owned_pack_ids.size(), 0)

func test_from_dict_rejects_non_array_field():
	# Defense-in-depth: if a save somehow carries a non-Array value for
	# owned_pack_ids (corrupted JSON, future field rename), hydration falls
	# back to an empty list instead of carrying garbage through has_pack.
	var restored := CosmeticInventory.from_dict({"owned_pack_ids": "not-an-array"})
	assert_eq(restored.owned_pack_ids.size(), 0)

func test_from_dict_clones_input_array():
	# Mutating the restored inventory must not stealth-mutate the source
	# dict's array reference. Matters once a single dict is fed to multiple
	# from_dict calls (e.g. a fan-out merge path).
	var src := ["cosmetic_coat_pack"]
	var restored := CosmeticInventory.from_dict({"owned_pack_ids": src})
	restored.grant("cosmetic_spell_effects")
	assert_eq(src.size(), 1, "source array unchanged after restored.grant")

func test_grant_appends_in_order():
	# owned_pack_ids preserves grant order — useful for "newest first"
	# display in the shop UI (#33) without an extra timestamp field.
	var inv := CosmeticInventory.new()
	inv.grant("cosmetic_coat_pack")
	inv.grant("cosmetic_spell_effects")
	inv.grant("cosmetic_dungeon_skins")
	assert_eq(inv.owned_pack_ids[0], "cosmetic_coat_pack")
	assert_eq(inv.owned_pack_ids[1], "cosmetic_spell_effects")
	assert_eq(inv.owned_pack_ids[2], "cosmetic_dungeon_skins")

# --- KittenSaveData wiring --------------------------------------------------

func test_kitten_save_data_to_dict_emits_cosmetic_packs():
	var sd := KittenSaveData.new()
	sd.cosmetic_packs = ["cosmetic_coat_pack"]
	var d := sd.to_dict()
	assert_true(d.has("cosmetic_packs"))
	assert_eq(d["cosmetic_packs"], ["cosmetic_coat_pack"])

func test_kitten_save_data_cosmetic_packs_round_trips():
	var sd := KittenSaveData.new()
	sd.cosmetic_packs = ["cosmetic_coat_pack", "cosmetic_spell_effects"]
	var restored := KittenSaveData.from_dict(sd.to_dict())
	assert_eq(restored.cosmetic_packs.size(), 2)
	assert_true(restored.cosmetic_packs.has("cosmetic_coat_pack"))
	assert_true(restored.cosmetic_packs.has("cosmetic_spell_effects"))

func test_kitten_save_data_to_cosmetic_inventory_hydrates_owned_packs():
	var sd := KittenSaveData.new()
	sd.cosmetic_packs = ["cosmetic_coat_pack", "cosmetic_dungeon_skins"]
	var inv := sd.to_cosmetic_inventory()
	assert_true(inv.has_pack("cosmetic_coat_pack"))
	assert_true(inv.has_pack("cosmetic_dungeon_skins"))
	assert_false(inv.has_pack("cosmetic_spell_effects"))

func test_kitten_save_data_from_character_captures_cosmetic_inventory():
	# The save layer captures the inventory's owned_pack_ids into the save's
	# cosmetic_packs field so future from_dict can rehydrate the same set.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	var inv := CosmeticInventory.new()
	inv.grant("cosmetic_coat_pack")
	inv.grant("cosmetic_spell_effects")
	var sd := KittenSaveData.from_character(c, null, null, null, inv)
	assert_eq(sd.cosmetic_packs.size(), 2)
	assert_true(sd.cosmetic_packs.has("cosmetic_coat_pack"))
	assert_true(sd.cosmetic_packs.has("cosmetic_spell_effects"))

func test_kitten_save_data_from_character_null_inventory_keeps_default():
	# Call sites that don't pass an inventory keep the field at default
	# (empty array). Locks the back-compat contract that the new trailing
	# param is opt-in.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var sd := KittenSaveData.from_character(c, null, null, null, null)
	assert_eq(sd.cosmetic_packs.size(), 0)

# --- GameState wiring -------------------------------------------------------

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_game_state_cosmetic_inventory_defaults_non_null():
	var gs := get_node("/root/GameState")
	assert_not_null(gs.cosmetic_inventory, "always non-null on autoload init")
	assert_eq(gs.cosmetic_inventory.owned_pack_ids.size(), 0,
		"fresh inventory starts empty")

func test_game_state_apply_merged_save_hydrates_cosmetic_inventory():
	var gs := get_node("/root/GameState")
	var save := KittenSaveData.new()
	save.cosmetic_packs = ["cosmetic_coat_pack", "cosmetic_dungeon_skins"]
	gs.apply_merged_save(save)
	assert_true(gs.cosmetic_inventory.has_pack("cosmetic_coat_pack"))
	assert_true(gs.cosmetic_inventory.has_pack("cosmetic_dungeon_skins"))
	assert_false(gs.cosmetic_inventory.has_pack("cosmetic_spell_effects"))
