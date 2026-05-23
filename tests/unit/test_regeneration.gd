extends GutTest

# Regression tests for the regeneration stat heal tick (Player._tick_regeneration).
# Root cause: CharacterData.regeneration was defined and allocatable but never
# consumed — Player._physics_process had no tick that applied HP recovery.
# Fix: _tick_regeneration uses a 1-second accumulator and calls data.heal(regeneration).

func _make_player(c: CharacterData) -> Player:
	var scene = load("res://scenes/player.tscn").instantiate()
	scene.data = c
	add_child_autofree(scene)
	return scene


func test_regeneration_heals_hp_after_one_second():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = c.max_hp - 5
	c.regeneration = 2
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp - 3, "1 second tick heals regeneration HP")


func test_regeneration_does_not_overheal():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = c.max_hp - 1
	c.regeneration = 5
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp, "heal is capped at max_hp")


func test_regeneration_does_not_tick_below_one_second():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = c.max_hp - 5
	c.regeneration = 3
	var p := _make_player(c)
	p._tick_regeneration(0.5)
	assert_eq(c.hp, c.max_hp - 5, "no heal before 1 second accumulates")
	p._tick_regeneration(0.4)
	assert_eq(c.hp, c.max_hp - 5, "still no heal at 0.9 s")
	p._tick_regeneration(0.1)
	assert_eq(c.hp, c.max_hp - 2, "heals once accumulator reaches 1.0 s")


func test_regeneration_zero_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = c.max_hp - 5
	c.regeneration = 0
	var p := _make_player(c)
	p._tick_regeneration(2.0)
	assert_eq(c.hp, c.max_hp - 5, "zero regeneration stat does not heal")


func test_regeneration_does_not_heal_dead_character():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = 0
	c.regeneration = 5
	var p := _make_player(c)
	p._tick_regeneration(2.0)
	assert_eq(c.hp, 0, "dead character does not receive regen")


func test_mp_regen_restores_mp_after_one_second():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.magic_points = c.max_mp - 5
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.magic_points, c.max_mp - 4, "1 second tick restores mp_regen MP")


func test_mp_regen_clamped_to_max_mp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.magic_points = c.max_mp - 1
	c.mp_regen = 5.0
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.magic_points, c.max_mp, "MP regen does not exceed max_mp")


func test_mp_regen_zero_is_noop_for_physical_classes():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.magic_points = 0
	c.max_mp = 0
	var p := _make_player(c)
	p._tick_regeneration(2.0)
	assert_eq(c.magic_points, 0, "Battle Kitten MP unchanged (mp_regen = 0)")


func test_mp_regen_sub_second_does_not_tick():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.magic_points = c.max_mp - 5
	var start_mp := c.magic_points
	var p := _make_player(c)
	p._tick_regeneration(0.5)
	assert_eq(c.magic_points, start_mp, "no MP regen before accumulator fills")


func test_hp_and_mp_regen_both_apply_same_tick():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.regeneration = 2
	c.hp = c.max_hp - 5
	c.magic_points = c.max_mp - 5
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp - 3, "HP regen applied")
	assert_eq(c.magic_points, c.max_mp - 4, "MP regen applied in same tick")


func test_allocating_regeneration_stat_has_in_game_effect():
	# End-to-end: StatAllocator.allocate -> regeneration > 0 -> tick heals.
	# Sleepy Kitten: regen gated to Sleepy classes (issue #142). Baseline
	# regen=1, +2 invested reaches the cap at 3.
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.skill_points = 3
	c.hp = c.max_hp - 4
	StatAllocator.allocate(c, {"regeneration": 2})
	assert_eq(c.regeneration, 3)
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp - 1, "allocated regeneration heals 1 HP per point per second")
