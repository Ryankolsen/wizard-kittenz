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
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.hp = c.max_hp - 5
	c.regeneration = 2
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp - 3, "1 second tick heals regeneration HP")


func test_regeneration_does_not_overheal():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.hp = c.max_hp - 1
	c.regeneration = 5
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp, "heal is capped at max_hp")


func test_regeneration_does_not_tick_below_one_second():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
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
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.hp = c.max_hp - 5
	c.regeneration = 0
	var p := _make_player(c)
	p._tick_regeneration(2.0)
	assert_eq(c.hp, c.max_hp - 5, "zero regeneration stat does not heal")


func test_regeneration_does_not_heal_dead_character():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.hp = 0
	c.regeneration = 5
	var p := _make_player(c)
	p._tick_regeneration(2.0)
	assert_eq(c.hp, 0, "dead character does not receive regen")


func test_allocating_regeneration_stat_has_in_game_effect():
	# End-to-end: StatAllocator.allocate -> regeneration > 0 -> tick heals.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.skill_points = 3
	c.hp = c.max_hp - 4  # Mage max_hp=8; deficit of 4 keeps character alive
	StatAllocator.allocate(c, {"regeneration": 3})
	assert_eq(c.regeneration, 3)
	var p := _make_player(c)
	p._tick_regeneration(1.0)
	assert_eq(c.hp, c.max_hp - 1, "allocated regeneration heals 1 HP per point per second")
