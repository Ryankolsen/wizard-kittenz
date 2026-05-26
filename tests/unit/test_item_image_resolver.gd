extends GutTest

func test_iron_sword_resolves_to_sword_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("iron_sword")),
		"res://assets/sprites/weapon_sword_sprite.png"
	)

func test_apprentice_wand_resolves_to_wand_sprite():
	assert_eq(
		ItemImageResolver.texture_path_for_item(ItemCatalog.find("apprentice_wand")),
		"res://assets/sprites/weapon_wand_sprite.png"
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
