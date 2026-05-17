extends GutTest

# PRD #132 / issue #134 — FloorRunSummary is a pure data holder
# assembled by main_scene at floor-clear time and passed to the
# congratulations screen for display. Tests construct objects
# directly without a scene tree.

func test_defaults_are_zero():
	var s := FloorRunSummary.new()
	assert_eq(s.floor_number, 0)
	assert_eq(s.enemies_slain, 0)
	assert_eq(s.xp_earned, 0)
	assert_eq(s.gold_earned, 0)

func test_constructor_assigns_all_fields():
	var s := FloorRunSummary.new(2, 3, 150, 42)
	assert_eq(s.floor_number, 2)
	assert_eq(s.enemies_slain, 3)
	assert_eq(s.xp_earned, 150)
	assert_eq(s.gold_earned, 42)

func test_delta_xp_calculation():
	var start_xp := 100
	var end_xp := 275
	var s := FloorRunSummary.new(1, 0, end_xp - start_xp, 0)
	assert_eq(s.xp_earned, 175)

func test_delta_gold_calculation():
	var start_gold := 20
	var end_gold := 55
	var s := FloorRunSummary.new(1, 0, 0, end_gold - start_gold)
	assert_eq(s.gold_earned, 35)

func test_enemies_slain_count():
	var s := FloorRunSummary.new(1, 7, 0, 0)
	assert_eq(s.enemies_slain, 7)

func test_floor_number():
	var s := FloorRunSummary.new(5, 0, 0, 0)
	assert_eq(s.floor_number, 5)

func test_fields_are_typed_int():
	var s := FloorRunSummary.new()
	assert_true(s.floor_number is int)
	assert_true(s.enemies_slain is int)
	assert_true(s.xp_earned is int)
	assert_true(s.gold_earned is int)
