extends GutTest

class _BareAttacker:
	extends RefCounted

class _StatAttacker:
	extends RefCounted
	var dexterity: int = 0
	var luck: int = 0

func test_hit_chance_base_is_85_percent():
	assert_almost_eq(HitResolver.hit_chance(0, 0), 0.85, 0.0001)

func test_hit_chance_dexterity_adds_2_percent_per_point():
	assert_almost_eq(HitResolver.hit_chance(1, 0), 0.87, 0.0001)
	assert_almost_eq(HitResolver.hit_chance(5, 0), 0.95, 0.0001)

func test_hit_chance_luck_adds_half_percent_per_point():
	assert_almost_eq(HitResolver.hit_chance(0, 2), 0.86, 0.0001)

func test_hit_chance_combined_dex_and_luck():
	assert_almost_eq(HitResolver.hit_chance(3, 4), 0.93, 0.0001)

func test_hit_chance_capped_at_98_percent():
	assert_true(HitResolver.hit_chance(99, 99) <= 0.98)
	assert_almost_eq(HitResolver.hit_chance(99, 99), 0.98, 0.0001)

func test_hit_chance_duck_typed_attacker_with_no_stats_does_not_crash():
	var bare := _BareAttacker.new()
	var chance: float = HitResolver.hit_chance(bare)
	assert_almost_eq(chance, 0.85, 0.0001)

func test_hit_chance_duck_typed_attacker_with_stats_uses_them():
	var a := _StatAttacker.new()
	a.dexterity = 5
	a.luck = 2
	assert_almost_eq(HitResolver.hit_chance(a), 0.96, 0.0001)

func test_hit_chance_negative_inputs_clamp_to_base():
	assert_almost_eq(HitResolver.hit_chance(-5, -10), 0.85, 0.0001)
	assert_almost_eq(HitResolver.hit_chance(-100, 0), 0.85, 0.0001)

func test_roll_hit_duck_typed_no_stats_does_not_crash():
	var bare := _BareAttacker.new()
	# Just exercise the path many times — must not crash.
	for i in range(20):
		var _r: bool = HitResolver.roll_hit(bare)
	assert_true(true, "no crash on duck-typed attacker without stats")

func test_crit_never_fires_at_zero_percent():
	for i in range(50):
		assert_false(CritResolver.roll_crit(0.0))

func test_crit_always_fires_at_100_percent():
	for i in range(50):
		assert_true(CritResolver.roll_crit(1.0))
