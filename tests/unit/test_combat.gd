extends GutTest

class _Stats:
	extends RefCounted
	var attack: int = 0

func _make_attacker(atk: int) -> _Stats:
	var s := _Stats.new()
	s.attack = atk
	return s

func test_damage_resolver_applies_attack_to_target_health():
	var attacker := _make_attacker(3)
	var target := Health.make(10, 0)
	var dealt := DamageResolver.apply(attacker, target)
	assert_eq(dealt, 3, "damage dealt equals attacker.attack when no defense")
	assert_eq(target.current, 7, "target.current reduced by attack value")

func test_hp_floor_at_zero():
	var attacker := _make_attacker(99)
	var target := Health.make(5, 0)
	var dealt := DamageResolver.apply(attacker, target)
	assert_eq(dealt, 5, "overkill returns only damage actually dealt")
	assert_eq(target.current, 0, "current cannot go below zero")
	assert_false(target.is_alive())

func test_attack_cooldown_blocks_rapid_repeats():
	var ac := AttackController.new()
	ac.cooldown = 0.4
	var attacker := _make_attacker(2)
	var target := Health.make(10, 0)

	assert_true(ac.try_attack(0.0), "first attack fires")
	DamageResolver.apply(attacker, target)
	assert_eq(target.current, 8)

	assert_false(ac.try_attack(0.1), "second attack within cooldown is blocked")
	# No DamageResolver call here — try_attack returned false, so no hit registers.
	assert_eq(target.current, 8, "no damage applied during cooldown")

	assert_true(ac.try_attack(0.5), "attack fires again after cooldown elapses")
	DamageResolver.apply(attacker, target)
	assert_eq(target.current, 6, "post-cooldown attack lands")

func test_defense_reduces_damage():
	var attacker := _make_attacker(5)
	var soft_target := Health.make(20, 0)
	var armored_target := Health.make(20, 2)

	DamageResolver.apply(attacker, soft_target)
	DamageResolver.apply(attacker, armored_target)

	var soft_loss := 20 - soft_target.current
	var armored_loss := 20 - armored_target.current
	assert_eq(soft_loss, 5, "no defense: full attack value")
	assert_eq(armored_loss, 3, "defense 2 reduces 5 attack to 3 damage")
	assert_lt(armored_loss, soft_loss, "armored target takes strictly less damage")

func test_minimum_one_damage_when_defense_exceeds_attack():
	var attacker := _make_attacker(2)
	var fortress := Health.make(10, 99)
	var dealt := DamageResolver.apply(attacker, fortress)
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
	var player := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var enemy_hp_before := enemy.hp
	DamageResolver.apply(player, enemy)
	assert_lt(enemy.hp, enemy_hp_before, "enemy.hp drops after player attack")

	var player_hp_before := player.hp
	DamageResolver.apply(enemy, player)
	assert_lt(player.hp, player_hp_before, "player.hp drops after enemy attack")

func test_health_make_initializes_full():
	var h := Health.make(15, 3)
	assert_eq(h.maximum, 15)
	assert_eq(h.current, 15, "new health starts at maximum")
	assert_eq(h.defense, 3)
	assert_true(h.is_alive())

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
