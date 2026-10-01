extends GutTest

# Issue #196: pure-data BubbleSelectionController. Owns the highlighted
# option index for a speech bubble and the transitions between options.
# No scene tree, no UI — just navigation logic over an enabled-mask.


func test_initial_cursor_on_first_enabled():
	var all_on := BubbleSelectionController.make(3, [true, true, true])
	assert_eq(all_on.current_index(), 0, "all-enabled: cursor starts at 0")

	var skip_first := BubbleSelectionController.make(3, [false, true, true])
	assert_eq(skip_first.current_index(), 1, "leading disabled row is skipped")


func test_move_next_advances_one():
	var c := BubbleSelectionController.make(3, [true, true, true])
	c.move_next()
	assert_eq(c.current_index(), 1)


func test_move_next_wraps_at_end():
	var c := BubbleSelectionController.make(3, [true, true, true])
	c.move_next()
	c.move_next()
	assert_eq(c.current_index(), 2, "advanced to last index")
	c.move_next()
	assert_eq(c.current_index(), 0, "wraps from end back to start")


func test_move_prev_wraps_at_start():
	var c := BubbleSelectionController.make(3, [true, true, true])
	c.move_prev()
	assert_eq(c.current_index(), 2, "wraps from start back to last")


func test_move_next_skips_disabled_middle():
	var c := BubbleSelectionController.make(3, [true, false, true])
	c.move_next()
	assert_eq(c.current_index(), 2, "skip over disabled middle row")


func test_move_prev_skips_disabled_middle():
	var c := BubbleSelectionController.make(3, [true, false, true])
	c.move_next()  # land on 2
	c.move_prev()
	assert_eq(c.current_index(), 0, "prev also skips disabled middle")


func test_confirm_returns_current_index_when_enabled():
	var c := BubbleSelectionController.make(3, [true, true, true])
	c.move_next()
	assert_eq(c.confirm(), 1, "returns currently-highlighted enabled index")


func test_confirm_returns_minus_one_when_no_options_enabled():
	var c := BubbleSelectionController.make(2, [false, false])
	assert_eq(c.current_index(), -1, "cursor sentinel when nothing enabled")
	assert_eq(c.confirm(), -1, "no enabled option -> confirm is a no-op")


func test_navigation_stable_when_all_disabled_except_one():
	var c := BubbleSelectionController.make(3, [false, true, false])
	assert_eq(c.current_index(), 1, "starts on the only enabled row")
	c.move_next()
	assert_eq(c.current_index(), 1, "stays put — no other enabled row to land on")
	c.move_prev()
	assert_eq(c.current_index(), 1, "prev also stays put")


func test_enabled_predicate_reevaluated_per_step():
	# Mask supplied as a Callable(index) -> bool. Flipping the underlying
	# state between moves must change navigation, proving the predicate is
	# not snapshotted at construction.
	var state := {"middle_on": true}
	var predicate := func(i: int) -> bool:
		if i == 1:
			return state["middle_on"]
		return true
	var c := BubbleSelectionController.make(3, predicate)

	c.move_next()
	assert_eq(c.current_index(), 1, "middle enabled: lands on it")

	# Disable middle, jump back to 0, then advance — should skip middle now.
	state["middle_on"] = false
	c.move_prev()
	assert_eq(c.current_index(), 0)
	c.move_next()
	assert_eq(c.current_index(), 2, "middle now disabled: navigation skips it")


func test_select_moves_cursor_to_enabled_index():
	var c := BubbleSelectionController.make(3, [true, true, true])
	c.select(2)
	assert_eq(c.current_index(), 2, "select moves cursor to the given enabled index")


func test_select_disabled_index_is_noop():
	var c := BubbleSelectionController.make(3, [true, false, true])
	c.select(1)
	assert_eq(c.current_index(), 0, "select does not move onto a disabled row")


func test_select_onto_nonadjacent_enabled_row():
	var c := BubbleSelectionController.make(4, [true, true, true, true])
	c.select(3)
	assert_eq(c.current_index(), 3, "select is not restricted to single-step movement")


func test_select_with_callable_mask_reevaluated():
	var state := {"middle_on": true}
	var predicate := func(i: int) -> bool:
		if i == 1:
			return state["middle_on"]
		return true
	var c := BubbleSelectionController.make(3, predicate)

	c.select(1)
	assert_eq(c.current_index(), 1, "callable mask: select lands on enabled index")

	state["middle_on"] = false
	c.select(0)
	assert_eq(c.current_index(), 0, "cursor moved to 0")
	c.select(1)
	assert_eq(c.current_index(), 0, "callable mask: select does not move onto now-disabled index")


func test_select_has_no_return_value_and_does_not_confirm():
	var c := BubbleSelectionController.make(2, [true, true])
	c.select(1)
	assert_eq(c.current_index(), 1, "cursor already reflects the move without calling confirm")
