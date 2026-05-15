extends GutTest

# PRD #85 wire-up for SpellEffectResolver: magic_attack adds to power,
# CritResolver doubles, magic_resistance mitigates (floor 1), evasion is
# NOT rolled on the magic path.

class FakeTarget:
	extends RefCounted
	var hp: int = 100
	var magic_resistance: int = 0
	var evasion: float = 0.0
	func is_alive() -> bool:
		return hp > 0
	func take_damage(amount: int) -> int:
		var dealt: int = mini(amount, hp)
		hp -= dealt
		return dealt

static func _force_crit() -> RandomNumberGenerator:
	# crit_chance >= 1.0 short-circuits without consuming rng; this rng
	# exists purely to give the resolver a stable seed in tests that may
	# add other rolls later.
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r

func _caster(magic_attack: int, crit_chance: float = 0.0) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.magic_attack = magic_attack
	c.crit_chance = crit_chance
	return c

func test_magic_attack_adds_to_spell_power():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 2, 1.0)
	var target := FakeTarget.new()
	var total := SpellEffectResolver.apply(spell, _caster(3), [target])
	assert_eq(total, 5, "spell.power(2) + magic_attack(3) = 5 damage")
	assert_eq(target.hp, 95)

func test_crit_doubles_effective_spell_power():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 4, 1.0)
	var target := FakeTarget.new()
	var total := SpellEffectResolver.apply(spell, _caster(0, 1.0), [target], _force_crit())
	assert_eq(total, 8, "crit doubles power 4 → 8")

func test_magic_resistance_mitigates_spell_damage():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 5, 1.0)
	var target := FakeTarget.new()
	target.magic_resistance = 2
	var total := SpellEffectResolver.apply(spell, _caster(0), [target])
	assert_eq(total, 3, "5 - 2 resistance = 3 damage")

func test_magic_resistance_floor_of_one():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 2, 1.0)
	var target := FakeTarget.new()
	target.magic_resistance = 99
	var total := SpellEffectResolver.apply(spell, _caster(0), [target])
	assert_eq(total, 1, "mitigation floors at 1")

func test_enemy_target_no_magic_resistance_field_no_crash():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 3, 1.0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	enemy.max_hp = 100
	enemy.hp = 100
	# EnemyData has no magic_resistance — should default to 0, no crash.
	var total := SpellEffectResolver.apply(spell, _caster(0), [enemy])
	assert_eq(total, 3, "full power lands when target has no magic_resistance field")
	assert_eq(enemy.hp, 97)

func test_magic_attack_zero_leaves_spell_power_unchanged():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 4, 1.0)
	var target := FakeTarget.new()
	var total := SpellEffectResolver.apply(spell, _caster(0), [target])
	assert_eq(total, 4)

func test_evasion_not_rolled_on_magic_path():
	# Spells always land — even a target with 1.0 evasion takes full damage.
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 3, 1.0)
	var target := FakeTarget.new()
	target.evasion = 1.0
	var total := SpellEffectResolver.apply(spell, _caster(0), [target])
	assert_eq(total, 3, "evasion ignored for spells")

func test_area_spell_hits_all_targets_with_resistance_applied():
	var spell := Spell.make("nova", "Nova", Spell.EffectKind.AREA, 6, 1.0)
	var t1 := FakeTarget.new()
	var t2 := FakeTarget.new()
	t2.magic_resistance = 2
	var total := SpellEffectResolver.apply(spell, _caster(1), [t1, t2])
	# t1: 6+1-0 = 7; t2: 6+1-2 = 5
	assert_eq(total, 12)
	assert_eq(t1.hp, 100 - 7)
	assert_eq(t2.hp, 100 - 5)

func test_null_caster_safe():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 3, 1.0)
	var target := FakeTarget.new()
	var total := SpellEffectResolver.apply(spell, null, [target])
	assert_eq(total, 3, "null caster degrades magic_attack/crit_chance to 0")

func test_spell_base_cooldown_captured_on_make():
	var spell := Spell.make("s", "S", Spell.EffectKind.DAMAGE, 1, 0.8)
	assert_eq(spell.base_cooldown, 0.8)
	assert_eq(spell.cooldown, 0.8)

# Issue #129: hp_cost cast-cost mechanic.

func test_hp_cost_deducts_from_caster_at_cast_time():
	var spell := Spell.make("hf", "Hissy Fit", Spell.EffectKind.DAMAGE, 5, 1.0, 2)
	var caster := _caster(0)
	caster.max_hp = 10
	caster.hp = 10
	assert_true(spell.cast(caster), "cast succeeds when hp > hp_cost")
	assert_eq(caster.hp, 8, "hp_cost(2) deducted from caster.hp(10) -> 8")

func test_hp_cost_blocks_cast_when_would_zero_caster():
	var spell := Spell.make("hf", "Hissy Fit", Spell.EffectKind.DAMAGE, 5, 1.0, 2)
	var caster := _caster(0)
	caster.max_hp = 10
	caster.hp = 2
	assert_false(spell.cast(caster), "cast blocked when caster.hp <= hp_cost")
	assert_eq(caster.hp, 2, "blocked cast leaves hp untouched")
	assert_true(spell.is_ready(), "blocked cast does not consume cooldown")

func test_zero_hp_cost_is_no_op_on_caster_hp():
	var spell := Spell.make("plain", "Plain", Spell.EffectKind.DAMAGE, 3, 1.0)
	var caster := _caster(0)
	caster.max_hp = 10
	caster.hp = 10
	assert_true(spell.cast(caster))
	assert_eq(caster.hp, 10, "hp_cost defaults to 0 — no deduction")

func test_hissy_fit_has_hp_cost():
	var tree := SkillTree.make_battle_kitten_tree()
	var node := tree.find("hissy_fit")
	assert_not_null(node, "battle kitten tree has hissy_fit node")
	assert_gt(node.spell.hp_cost, 0, "hissy_fit spell carries a non-zero hp_cost")
