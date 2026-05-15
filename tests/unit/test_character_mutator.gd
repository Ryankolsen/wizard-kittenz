extends GutTest

# CharacterMutator is the write gateway for CharacterData. Tests verify:
#   - all write methods land on the underlying CharacterData
#   - callers don't need to know about DamageResolver or ReviveSystem
#   - null data is safe throughout

func _make_mage() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.MAGE)

func _make_slime_attacker(attack: int) -> EnemyData:
	var e := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e.attack = attack
	return e

func _force_hit_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for s in range(1, 100000):
		rng.seed = s
		if rng.randf() < 0.85:
			rng.seed = s
			return rng
	return rng

# --- apply_damage ------------------------------------------------------------

func test_apply_damage_reduces_character_data_hp():
	var c := _make_mage()
	var hp_before := c.hp
	var m := CharacterMutator.new(c)
	var dealt := m.apply_damage(_make_slime_attacker(3), _force_hit_rng())
	assert_gt(dealt, 0, "damage lands through the mutator")
	assert_eq(c.hp, hp_before - dealt, "CharacterData.hp reduced")

func test_apply_damage_respects_defense():
	var c := _make_mage()
	c.defense = 99
	var m := CharacterMutator.new(c)
	var dealt := m.apply_damage(_make_slime_attacker(1), _force_hit_rng())
	assert_eq(dealt, 1, "defense floor of 1 passes through unchanged")

func test_apply_damage_null_attacker_returns_zero():
	var c := _make_mage()
	var hp_before := c.hp
	var dealt := CharacterMutator.new(c).apply_damage(null)
	assert_eq(dealt, 0)
	assert_eq(c.hp, hp_before)

func test_apply_damage_null_data_returns_zero():
	var m := CharacterMutator.new(null)
	assert_eq(m.apply_damage(_make_slime_attacker(5)), 0)

# --- revive ------------------------------------------------------------------

func test_revive_restores_hp_to_half_max():
	var c := _make_mage()
	c.max_hp = 10
	c.hp = 0
	var m := CharacterMutator.new(c)
	var result := m.revive()
	assert_eq(result, 5)
	assert_eq(c.hp, 5, "CharacterData.hp restored to 50% of max_hp")

func test_revive_min_one_floor():
	var c := _make_mage()
	c.max_hp = 1
	c.hp = 0
	CharacterMutator.new(c).revive()
	assert_eq(c.hp, 1)

func test_revive_null_data_returns_zero():
	var m := CharacterMutator.new(null)
	assert_eq(m.revive(), 0)

# --- apply_stat_delta --------------------------------------------------------

func test_apply_stat_delta_increases_stat():
	var c := _make_mage()
	var before := c.attack
	CharacterMutator.new(c).apply_stat_delta("attack", 3.0)
	assert_eq(c.attack, before + 3, "apply_stat_delta mutates CharacterData")

func test_apply_stat_delta_can_subtract():
	var c := _make_mage()
	c.defense = 5
	CharacterMutator.new(c).apply_stat_delta("defense", -2.0)
	assert_eq(c.defense, 3)

func test_apply_stat_delta_null_data_no_crash():
	CharacterMutator.new(null).apply_stat_delta("attack", 1.0)

# --- idempotent equip/unequip round-trip ------------------------------------

func test_equip_then_unequip_restores_original_stat():
	var c := _make_mage()
	var base_attack := c.attack
	var m := CharacterMutator.new(c)
	m.apply_stat_delta("attack", 5.0)
	assert_eq(c.attack, base_attack + 5, "bonus applied")
	m.apply_stat_delta("attack", -5.0)
	assert_eq(c.attack, base_attack, "bonus removed; stat returned to base")
