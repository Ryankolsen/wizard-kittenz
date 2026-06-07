extends GutTest

# Slice 8 (issue #367). PotionImageResolver maps a PotionDefinition to its icon:
# generic per-effect-kind art reused across every potion of the kind, with a
# per-id override reserved for future special potions. Mirrors the
# ItemImageResolver tier-sprite contract.

func test_health_potion_resolves_to_red_bottle():
	assert_eq(
		PotionImageResolver.texture_path_for(PotionCatalog.find("health_potion")),
		"res://assets/sprites/potion_red_sprite.png"
	)

func test_mana_potion_resolves_to_blue_bottle():
	assert_eq(
		PotionImageResolver.texture_path_for(PotionCatalog.find("mana_potion")),
		"res://assets/sprites/potion_blue_sprite.png"
	)

func test_shield_potion_resolves_to_green_bottle():
	# Gold is reserved for future special potions, so the base shield is green.
	assert_eq(
		PotionImageResolver.texture_path_for(PotionCatalog.find("shield_potion")),
		"res://assets/sprites/potion_green_sprite.png"
	)

func test_new_potion_reuses_generic_art_by_kind():
	# The reuse guarantee: a brand-new potion sharing an existing effect kind
	# gets that kind's bottle with zero new art.
	var custom := PotionDefinition.make(
		"mega_health", "Mega Health Potion", "Restores 100% of your max HP.",
		PotionDefinition.EffectKind.HEAL_PERCENT, 100, 0.0, "healing")
	assert_eq(
		PotionImageResolver.texture_path_for(custom),
		"res://assets/sprites/potion_red_sprite.png"
	)

func test_null_resolves_to_empty():
	assert_eq(PotionImageResolver.texture_path_for(null), "")

func test_texture_for_loads_a_texture():
	var tex := PotionImageResolver.texture_for(PotionCatalog.find("mana_potion"))
	assert_not_null(tex)

func test_catalog_seeds_every_potion_with_an_icon():
	for def in PotionCatalog.all():
		assert_not_null(def.icon, "%s must ship with an icon" % def.id)
