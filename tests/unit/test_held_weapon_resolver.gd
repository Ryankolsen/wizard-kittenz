extends GutTest

# HeldWeaponResolver (PRD #280 / issue #281). Pins the pure mapping from
# equipped weapon + character class to { pose, texture, armed } so both the
# Character-page avatar and combat resolve identically.

func test_iron_sword_battle_resolves_armed_with_battle_pose_and_mackerel_texture():
	var item := ItemCatalog.find("iron_sword")
	var out := HeldWeaponResolver.resolve(item, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_true(out[HeldWeaponResolver.ARMED_KEY], "iron_sword equipped → armed")
	assert_eq(out[HeldWeaponResolver.TEXTURE_KEY],
		"res://assets/sprites/weapon_slippery_mackerel.png")
	var def: WeaponDefinition = out[HeldWeaponResolver.DEFINITION_KEY]
	assert_not_null(def, "battle weapon resolves to a non-null definition")
	var battle := WeaponDefinition.for_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(def.attack_type, battle.attack_type, "pose attack_type matches battle preset")
	assert_eq(def.anchor_offset, battle.anchor_offset, "pose anchor_offset matches battle preset")

func test_healing_wand_sleepy_uses_mushroom_texture():
	# Slice 3 (issue #481): healing_wand now has a per-id sprite, so the
	# texture is the Mushroom-on-a-Stick art, not the class-default staff.
	var item := ItemCatalog.find("healing_wand")
	var out := HeldWeaponResolver.resolve(item, CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_true(out[HeldWeaponResolver.ARMED_KEY])
	assert_eq(out[HeldWeaponResolver.TEXTURE_KEY],
		"res://assets/sprites/weapon_mushroom_on_a_stick.png")

func test_heavy_club_chonk_uses_mug_pose_and_pint_texture():
	# Slice 4 (issue #482): heavy_club now has a per-id sprite, so the
	# texture is the Cheap Tavern Pint art, not the class-default mug.
	var item := ItemCatalog.find("heavy_club")
	var out := HeldWeaponResolver.resolve(item, CharacterData.CharacterClass.CHONK_KITTEN)
	assert_true(out[HeldWeaponResolver.ARMED_KEY])
	assert_eq(out[HeldWeaponResolver.TEXTURE_KEY],
		"res://assets/sprites/weapon_cheap_tavern_pint.png")
	var def: WeaponDefinition = out[HeldWeaponResolver.DEFINITION_KEY]
	var chonk := WeaponDefinition.for_class(CharacterData.CharacterClass.CHONK_KITTEN)
	assert_eq(def.sprite_scale, chonk.sprite_scale, "chonk preset upright-mug scaling preserved")
	assert_eq(def.weapon_offset, chonk.weapon_offset, "chonk preset weapon_offset preserved")

func test_null_item_is_unarmed_with_empty_texture():
	var out := HeldWeaponResolver.resolve(null, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_false(out[HeldWeaponResolver.ARMED_KEY], "no item → unarmed")
	assert_eq(out[HeldWeaponResolver.TEXTURE_KEY], "", "no texture path when unarmed")
	assert_null(out[HeldWeaponResolver.DEFINITION_KEY], "no pose definition when unarmed")
