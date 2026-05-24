extends GutTest

# PRD #223 / issue #226 (slice 3 finished wiring sleepy + chonk). WeaponDefinition
# is a pure Resource. All four kitten classes now return a preset from for_class;
# other character classes (cat-tier etc.) still return null.

func test_battle_preset_uses_sword_sprite_with_swing_type() -> void:
	var d := WeaponDefinition.battle()
	assert_eq(d.texture_path, "res://assets/sprites/weapon_sword_sprite.png")
	assert_eq(d.attack_type, WeaponDefinition.AttackType.SWING)
	assert_gt(d.swing_arc, 0.0)

func test_for_class_returns_battle_preset_for_battle_kitten() -> void:
	var d := WeaponDefinition.for_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_not_null(d)
	assert_eq(d.attack_type, WeaponDefinition.AttackType.SWING)

# Slice 2 (issue #225) test 3: wizard preset wires the wand sprite as a CAST
# attack so AttackChoreographer dispatches to WeaponPivot.cast (thrust),
# not swing.
func test_wizard_preset_uses_wand_sprite_with_cast_type() -> void:
	var d := WeaponDefinition.wizard()
	assert_eq(d.texture_path, "res://assets/sprites/weapon_wand_sprite.png")
	assert_eq(d.attack_type, WeaponDefinition.AttackType.CAST)
	assert_gt(d.thrust_distance, 0.0)

func test_for_class_returns_wizard_preset_for_wizard_kitten() -> void:
	var d := WeaponDefinition.for_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_not_null(d)
	assert_eq(d.attack_type, WeaponDefinition.AttackType.CAST)

func test_sleepy_preset_uses_staff_sprite_with_swing_type() -> void:
	var d := WeaponDefinition.sleepy()
	assert_eq(d.texture_path, "res://assets/sprites/weapon_staff_sprite.png")
	assert_eq(d.attack_type, WeaponDefinition.AttackType.SWING)
	assert_gt(d.swing_arc, 0.0)

func test_chonk_preset_uses_mug_sprite_with_swing_type() -> void:
	var d := WeaponDefinition.chonk()
	assert_eq(d.texture_path, "res://assets/sprites/weapon_mug_sprite.png")
	assert_eq(d.attack_type, WeaponDefinition.AttackType.SWING)
	assert_gt(d.swing_arc, 0.0)

func test_chonk_mug_pivot_offset_differs_from_horizontal_stick_weapons() -> void:
	# The mug sprite (47x48) has its grip on the LEFT edge rather than centered
	# like the 48x12 sword/staff/wand. weapon_offset must shift the sprite away
	# from the pivot so rotation happens around the handle, not the geometric
	# center. Battle's weapon_offset is ZERO; chonk's must be non-zero on x.
	var battle_def := WeaponDefinition.battle()
	var chonk_def := WeaponDefinition.chonk()
	assert_ne(chonk_def.weapon_offset, battle_def.weapon_offset)
	assert_gt(chonk_def.weapon_offset.x, 0.0,
		"mug sprite shifts right of the pivot so rotation centers on the handle")

func test_for_class_returns_sleepy_preset_for_sleepy_kitten() -> void:
	var d := WeaponDefinition.for_class(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_not_null(d)
	assert_eq(d.texture_path, "res://assets/sprites/weapon_staff_sprite.png")

func test_for_class_returns_chonk_preset_for_chonk_kitten() -> void:
	var d := WeaponDefinition.for_class(CharacterData.CharacterClass.CHONK_KITTEN)
	assert_not_null(d)
	assert_eq(d.texture_path, "res://assets/sprites/weapon_mug_sprite.png")

func test_total_duration_sums_phases() -> void:
	var d := WeaponDefinition.new()
	d.windup_duration = 0.1
	d.strike_duration = 0.2
	d.recovery_duration = 0.3
	assert_almost_eq(d.total_duration(), 0.6, 0.0001)
