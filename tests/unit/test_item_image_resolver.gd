extends GutTest

func test_iron_sword_resolves_to_slippery_mackerel_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("iron_sword")),
		"res://assets/sprites/weapon_slippery_mackerel.png"
	)

func test_unconverted_weapon_falls_back_to_class_default():
	# Slice 4 of PRD #273 finished the per-id table — every catalog weapon now
	# resolves per-id, so the class-default fallback branch is only reachable
	# via a synthetic item whose id is not in _PER_ID_SPRITES. Pin that branch
	# directly here.
	var synth := ItemData.make(
		"unconverted_test_only", "X",
		ItemData.Slot.WEAPON, ItemData.Rarity.COMMON,
		"attack", 1.0,
		[CharacterData.CharacterClass.CHONK_KITTEN]
	)
	assert_eq(
		ItemImageResolver.texture_path_for_item(synth),
		"res://assets/sprites/weapon_mug_sprite.png"
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

func test_healing_wand_resolves_to_mushroom_on_a_stick_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("healing_wand")),
		"res://assets/sprites/weapon_mushroom_on_a_stick.png"
	)

func test_sleepy_weapons_resolve_to_unique_sprites():
	# Slice 3 of PRD #273: all 7 Sleepy weapon ids must resolve to their
	# per-id sprite (the fallback to weapon_staff_sprite.png is no longer hit).
	var expected := {
		"healing_wand": "res://assets/sprites/weapon_mushroom_on_a_stick.png",
		"feather_wand": "res://assets/sprites/weapon_lollipop_wand.png",
		"dreamcatcher_staff": "res://assets/sprites/weapon_dreamcatcher_staff.png",
		"cloud_staff": "res://assets/sprites/weapon_cloud_puff_wand.png",
		"shop_lullaby_wand": "res://assets/sprites/weapon_warm_milk_ladle.png",
		"lullaby_scepter": "res://assets/sprites/weapon_moonbeam_scepter.png",
		"starlight_caduceus": "res://assets/sprites/weapon_caduceus_of_catnaps.png",
	}
	for id in expected.keys():
		assert_eq(
			ItemImageResolver.texture_path_for_item(ItemCatalog.find(id)),
			expected[id],
			"id %s resolves to wrong sprite" % id
		)

func test_heavy_club_resolves_to_cheap_tavern_pint_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("heavy_club")),
		"res://assets/sprites/weapon_cheap_tavern_pint.png"
	)

func test_chonk_weapons_resolve_to_unique_sprites():
	# Slice 4 of PRD #273: all 7 Chonk weapon ids must resolve to their per-id
	# beer sprite (the fallback to weapon_mug_sprite.png is no longer hit).
	var expected := {
		"heavy_club": "res://assets/sprites/weapon_cheap_tavern_pint.png",
		"oak_cudgel": "res://assets/sprites/weapon_wooden_tankard.png",
		"shop_oak_mallet": "res://assets/sprites/weapon_sloshing_pint_glass.png",
		"spiked_mace": "res://assets/sprites/weapon_iron_banded_stein.png",
		"bone_crusher": "res://assets/sprites/weapon_hefty_stein.png",
		"earthshaker_hammer": "res://assets/sprites/weapon_mighty_keg.png",
		"mountain_maul": "res://assets/sprites/weapon_golden_chalice_of_ale.png",
	}
	for id in expected.keys():
		assert_eq(
			ItemImageResolver.texture_path_for_item(ItemCatalog.find(id)),
			expected[id],
			"id %s resolves to wrong sprite" % id
		)

func test_armor_resolves_to_empty():
	assert_eq(ItemImageResolver.texture_path_for_item(ItemCatalog.find("chain_mail")), "")

func test_accessory_resolves_to_empty():
	assert_eq(ItemImageResolver.texture_path_for_item(ItemCatalog.find("shadow_amulet")), "")

func test_null_resolves_to_empty():
	assert_eq(ItemImageResolver.texture_path_for_item(null), "")

func test_weapon_with_no_resolvable_class_resolves_to_empty():
	var item := ItemData.make(
		"x", "X", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON,
		"attack", 1.0, []
	)
	assert_eq(ItemImageResolver.texture_path_for_item(item), "")
