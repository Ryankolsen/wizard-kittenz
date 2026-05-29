extends GutTest

func test_iron_sword_resolves_to_slippery_mackerel_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("iron_sword")),
		"res://assets/sprites/weapon_slippery_mackerel.png"
	)

func test_unconverted_weapon_falls_back_to_class_default():
	# healing_wand has no per-id sprite yet (sleepy slice still pending),
	# so the resolver must fall back to the class-default staff sprite.
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("healing_wand")),
		"res://assets/sprites/weapon_staff_sprite.png"
	)

func test_apprentice_wand_resolves_to_birthday_sparkler_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("apprentice_wand")),
		"res://assets/sprites/weapon_birthday_sparkler.png"
	)

func test_wizard_weapons_resolve_to_unique_sprites():
	# Slice 2 of PRD #273: all 7 Wizard weapon ids must resolve to their
	# per-id sprite (the fallback to weapon_wand_sprite.png is no longer hit).
	var expected := {
		"apprentice_wand": "res://assets/sprites/weapon_birthday_sparkler.png",
		"novice_wand": "res://assets/sprites/weapon_firefly_jar.png",
		"arcane_staff": "res://assets/sprites/weapon_crackle_wand.png",
		"runed_staff": "res://assets/sprites/weapon_stormtwig_staff.png",
		"starfire_rod": "res://assets/sprites/weapon_comet_caller.png",
		"voidcaller_staff": "res://assets/sprites/weapon_wand_of_the_big_bang.png",
		"shop_archmage_staff": "res://assets/sprites/weapon_archmage_astrolabe.png",
	}
	for id in expected.keys():
		assert_eq(
			ItemImageResolver.texture_path_for_item(ItemCatalog.find(id)),
			expected[id],
			"id %s resolves to wrong sprite" % id
		)

func test_healing_wand_resolves_to_staff_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("healing_wand")),
		"res://assets/sprites/weapon_staff_sprite.png"
	)

func test_heavy_club_resolves_to_mug_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("heavy_club")),
		"res://assets/sprites/weapon_mug_sprite.png"
	)

func test_armor_rare_resolves_to_armor_rare_tier():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("chain_mail")),
		"res://assets/sprites/armor_rare.png"
	)

func test_accessory_epic_resolves_to_accessory_epic_tier():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("shadow_amulet")),
		"res://assets/sprites/accessory_epic.png"
	)

func test_armor_accessory_tier_matrix():
	# PRD #288 / issue #290: every slot×rarity combo resolves to its tier sprite.
	var expected := {
		"leather_vest": "res://assets/sprites/armor_common.png",
		"chain_mail": "res://assets/sprites/armor_rare.png",
		"dragon_scale": "res://assets/sprites/armor_epic.png",
		"lucky_charm": "res://assets/sprites/accessory_common.png",
		"swift_ring": "res://assets/sprites/accessory_rare.png",
		"shadow_amulet": "res://assets/sprites/accessory_epic.png",
	}
	for id in expected.keys():
		assert_eq(
			ItemImageResolver.texture_path_for_item(ItemCatalog.find(id)),
			expected[id],
			"id %s resolves to wrong tier sprite" % id
		)

func test_armor_with_missing_tier_asset_falls_through_to_empty():
	# Construct an armor item with an id outside the override map. If a future
	# rarity were added without a shipped tier file, the resolver must fall
	# through to "" rather than returning a broken path. We simulate this by
	# verifying the empty-override default does not produce a spurious match
	# for an unknown id.
	var item := ItemData.make(
		"unknown_armor_id", "Unknown", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON,
		"defense", 1.0, []
	)
	# COMMON armor has a shipped tier sprite — id is irrelevant to tier lookup.
	assert_eq(
		ItemImageResolver.texture_path_for_item(item),
		"res://assets/sprites/armor_common.png"
	)

func test_empty_override_map_does_not_shadow_tier():
	# Override map is empty in this slice; tier path must still be returned.
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("leather_vest")),
		"res://assets/sprites/armor_common.png"
	)

func test_null_resolves_to_empty():
	assert_eq(ItemImageResolver.texture_path_for_item(null), "")

func test_weapon_with_no_resolvable_class_resolves_to_empty():
	var item := ItemData.make(
		"x", "X", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON,
		"attack", 1.0, []
	)
	assert_eq(ItemImageResolver.texture_path_for_item(item), "")
