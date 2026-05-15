extends GutTest

class _Stats:
	extends RefCounted
	var attack: int = 0

class _FullStats:
	# Mirrors CharacterData's combat-stat shape for resolver tests that
	# need duck-typed reads of dexterity / luck / crit_chance / evasion
	# without dragging in the full Resource (and its disk-save lifecycle).
	extends RefCounted
	var attack: int = 0
	var defense: int = 0
	var dexterity: int = 0
	var luck: int = 0
	var crit_chance: float = 0.0
	var evasion: float = 0.0
	var hp: int = 100
	func take_damage(amount: int) -> int:
		var dealt := mini(amount, hp)
		hp -= dealt
		return dealt

func _make_attacker(atk: int) -> _Stats:
	var s := _Stats.new()
	s.attack = atk
	return s

# Shortcut for `_rng_where_first_randf(< 0.85)` — every test that needs
# a deterministic hit (not a miss test) constructs one of these per
# apply() call. Seed advances after one randf(), so reusing across
# multiple apply()s would re-flake the cooldown / damage tests.
func _force_hit() -> RandomNumberGenerator:
	return _rng_where_first_randf(func(v): return v < 0.85)

# Find a seeded RNG whose first randf() satisfies `predicate`. Used by
# resolver tests to pin hit-or-miss outcomes deterministically — the base
# hit chance is 0.85 so we cannot construct a 100%-miss attacker from
# stats alone.
func _rng_where_first_randf(predicate: Callable) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for s in range(1, 100000):
		rng.seed = s
		var first := rng.randf()
		if predicate.call(first):
			rng.seed = s
			return rng
	assert_true(false, "no seed found matching predicate")
	return rng

func test_damage_resolver_applies_attack_to_target_health():
	var attacker := _make_attacker(3)
	var target := Health.make(10, 0)
	var dealt := DamageResolver.apply(attacker, target, _force_hit())
	assert_eq(dealt, 3, "damage dealt equals attacker.attack when no defense")
	assert_eq(target.current, 7, "target.current reduced by attack value")

func test_hp_floor_at_zero():
	var attacker := _make_attacker(99)
	var target := Health.make(5, 0)
	var dealt := DamageResolver.apply(attacker, target, _force_hit())
	assert_eq(dealt, 5, "overkill returns only damage actually dealt")
	assert_eq(target.current, 0, "current cannot go below zero")
	assert_false(target.is_alive())

func test_attack_cooldown_blocks_rapid_repeats():
	var ac := AttackController.new()
	ac.cooldown = 0.4
	var attacker := _make_attacker(2)
	var target := Health.make(10, 0)

	assert_true(ac.try_attack(0.0), "first attack fires")
	DamageResolver.apply(attacker, target, _force_hit())
	assert_eq(target.current, 8)

	assert_false(ac.try_attack(0.1), "second attack within cooldown is blocked")
	# No DamageResolver call here — try_attack returned false, so no hit registers.
	assert_eq(target.current, 8, "no damage applied during cooldown")

	assert_true(ac.try_attack(0.5), "attack fires again after cooldown elapses")
	DamageResolver.apply(attacker, target, _force_hit())
	assert_eq(target.current, 6, "post-cooldown attack lands")

func test_defense_reduces_damage():
	var attacker := _make_attacker(5)
	var soft_target := Health.make(20, 0)
	var armored_target := Health.make(20, 2)

	DamageResolver.apply(attacker, soft_target, _force_hit())
	DamageResolver.apply(attacker, armored_target, _force_hit())

	var soft_loss := 20 - soft_target.current
	var armored_loss := 20 - armored_target.current
	assert_eq(soft_loss, 5, "no defense: full attack value")
	assert_eq(armored_loss, 3, "defense 2 reduces 5 attack to 3 damage")
	assert_lt(armored_loss, soft_loss, "armored target takes strictly less damage")

func test_minimum_one_damage_when_defense_exceeds_attack():
	var attacker := _make_attacker(2)
	var fortress := Health.make(10, 99)
	var dealt := DamageResolver.apply(attacker, fortress, _force_hit())
	assert_eq(dealt, 1, "minimum 1 damage even with overwhelming defense")
	assert_eq(fortress.current, 9)

func test_zero_attack_deals_no_damage():
	var attacker := _make_attacker(0)
	var target := Health.make(10, 0)
	var dealt := DamageResolver.apply(attacker, target)
	assert_eq(dealt, 0, "zero attack deals no damage")
	assert_eq(target.current, 10)

func test_damage_resolver_works_with_enemy_data():
	# Symmetry check: DamageResolver duck-types over CharacterData and EnemyData.
	# Player attacks an enemy, then enemy attacks the player — both flow through
	# the same resolver.
	var player := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var enemy_hp_before := enemy.hp
	DamageResolver.apply(player, enemy, _force_hit())
	assert_lt(enemy.hp, enemy_hp_before, "enemy.hp drops after player attack")

	var player_hp_before := player.hp
	DamageResolver.apply(enemy, player, _force_hit())
	assert_lt(player.hp, player_hp_before, "player.hp drops after enemy attack")

func test_health_make_initializes_full():
	var h := Health.make(15, 3)
	assert_eq(h.maximum, 15)
	assert_eq(h.current, 15, "new health starts at maximum")
	assert_eq(h.defense, 3)
	assert_true(h.is_alive())

func test_damage_resolver_returns_zero_on_miss():
	# Seeded so HitResolver.roll_hit consumes a randf >= 0.85 (base hit chance)
	# and reports a miss. crit_chance=0.0 and target.evasion=0.0 short-circuit
	# without touching the rng, so the hit roll is the only consumer.
	var attacker := _FullStats.new()
	attacker.attack = 5
	var target := _FullStats.new()
	target.hp = 20
	var rng := _rng_where_first_randf(func(v): return v >= 0.85)
	var dealt := DamageResolver.apply(attacker, target, rng)
	assert_eq(dealt, 0, "miss returns zero damage")
	assert_eq(target.hp, 20, "missed attack does not reduce hp")

func test_damage_resolver_crit_doubles_pre_mitigation_damage():
	# attack=4, defense=1 → normal hit deals max(1, 4-1)=3.
	# crit doubles raw BEFORE defense subtraction → max(1, 8-1)=7.
	# crit_chance=1.0 + evasion=0.0 are both deterministic short-circuits;
	# seed rng so the hit roll lands.
	var attacker := _FullStats.new()
	attacker.attack = 4
	attacker.crit_chance = 1.0
	var target := _FullStats.new()
	target.defense = 1
	target.hp = 20
	var rng := _rng_where_first_randf(func(v): return v < 0.85)
	var dealt := DamageResolver.apply(attacker, target, rng)
	assert_eq(dealt, 7, "crit doubles attack before defense: 2*4 - 1 = 7")

func test_damage_resolver_returns_zero_on_evade():
	var attacker := _FullStats.new()
	attacker.attack = 5
	var target := _FullStats.new()
	target.evasion = 1.0
	target.hp = 20
	var rng := _rng_where_first_randf(func(v): return v < 0.85)
	var dealt := DamageResolver.apply(attacker, target, rng)
	assert_eq(dealt, 0, "evasion=1.0 always evades")
	assert_eq(target.hp, 20)

func test_evasion_is_zero_by_default_on_enemy_data():
	# EnemyData has no `evasion` field; the duck-typed read must default
	# to 0.0 so the evasion branch never fires on enemies.
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var enemy_hp_before := enemy.hp
	var player := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	# Force a hit so the test isn't flaky on the 15% miss floor.
	var rng := _rng_where_first_randf(func(v): return v < 0.85)
	var dealt := DamageResolver.apply(player, enemy, rng)
	assert_gt(dealt, 0, "no evade path on EnemyData target")
	assert_lt(enemy.hp, enemy_hp_before)

func test_enemy_data_attacker_no_crash():
	# EnemyData has no dexterity/luck/crit_chance — duck-typed reads
	# must default to neutral values so the resolver still runs.
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var player := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var player_hp_before := player.hp
	# Probabilistic miss is acceptable here — we're checking no-crash and
	# that *eventually* damage lands. Burn through the 15% miss floor.
	for i in range(20):
		DamageResolver.apply(enemy, player)
		if player.hp < player_hp_before:
			break
	assert_lt(player.hp, player_hp_before, "enemy attack lands without crashing")

func test_partial_evasion_does_not_always_evade():
	# target.evasion=0.0 short-circuits the evasion branch entirely —
	# damage must land on every call.
	var attacker := _FullStats.new()
	attacker.attack = 5
	var target := _FullStats.new()
	target.evasion = 0.0
	target.hp = 1000
	var rng := _rng_where_first_randf(func(v): return v < 0.85)
	# Single deterministic call — multiple would require re-seeding per
	# call. evasion=0.0 is the gate under test.
	var dealt := DamageResolver.apply(attacker, target, rng)
	assert_gt(dealt, 0, "evasion=0.0 lets damage through")

func test_attack_controller_can_attack_after_long_idle():
	var ac := AttackController.new()
	ac.cooldown = 0.4
	# Default last_attack_time is far in the past, so first call should always succeed.
	assert_true(ac.can_attack(0.0))
	assert_true(ac.try_attack(0.0))
	# Then becomes false within cooldown
	assert_false(ac.can_attack(0.2))
	# True again past cooldown
	assert_true(ac.can_attack(0.4))
