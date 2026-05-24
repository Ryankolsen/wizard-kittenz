extends GutTest

# Slice 1 of PRD #223 / issue #224. WeaponDefinition is a pure Resource;
# the battle preset is the only one wired in slice 1 — other classes return
# null from for_class until slices 2-3.

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

func test_for_class_returns_null_for_other_classes_pre_slice_3() -> void:
	# Pre-slice-3 sentinel — sleepy/chonk have no WeaponDefinition yet,
	# so player.gd falls back to the legacy _play_attack_flash path for them.
	assert_null(WeaponDefinition.for_class(CharacterData.CharacterClass.SLEEPY_KITTEN))
	assert_null(WeaponDefinition.for_class(CharacterData.CharacterClass.CHONK_KITTEN))

func test_total_duration_sums_phases() -> void:
	var d := WeaponDefinition.new()
	d.windup_duration = 0.1
	d.strike_duration = 0.2
	d.recovery_duration = 0.3
	assert_almost_eq(d.total_duration(), 0.6, 0.0001)
