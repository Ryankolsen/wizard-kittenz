extends GutTest

# Minimap slice 4 (#308): floor advance must construct a fresh
# FloorMapState with only the new floor's start room revealed; the prior
# floor's state is left untouched. Production wiring runs through
# main_scene._start_new_dungeon which builds a new DungeonRunController
# (and thus a fresh state via start()) on each scene reload — this test
# pins the pure data contract on FloorMapState.with_start_revealed.

func test_floor_advance_constructs_fresh_state_with_start_prerevealed():
	var prior := FloorMapState.new()
	prior.mark_revealed(0)
	prior.mark_revealed(1)
	prior.mark_revealed(4)
	var fresh := FloorMapState.with_start_revealed(9)
	assert_false(prior == fresh, "advance must hand back a NEW instance")
	assert_true(fresh.is_revealed(9), "new floor's start must be pre-revealed")
	assert_eq(fresh.revealed_ids().size(), 1, "only the new start is revealed")
	# Prior floor's state untouched — important because in solo the run
	# could in theory still hold a reference to the old state if a future
	# floor-advance path forgets to swap the reference cleanly.
	var prior_ids: Array = prior.revealed_ids()
	assert_eq(prior_ids.size(), 3)
	assert_true(prior_ids.has(0))
	assert_true(prior_ids.has(1))
	assert_true(prior_ids.has(4))

# Controller.start drives the production "fresh state on floor advance"
# path (main_scene._start_new_dungeon constructs a new controller per
# floor). Pins that start() installs the FloorMapState with start_id
# pre-revealed — no relying on a separate _setup_minimap pass.
func test_controller_start_initializes_floor_map_state_with_start_prerevealed():
	var dungeon := DungeonGenerator.generate(42)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	assert_not_null(ctrl.floor_map_state)
	assert_true(ctrl.floor_map_state.is_revealed(dungeon.start_id))
	assert_eq(ctrl.floor_map_state.revealed_ids().size(), 1)
