extends GutTest

# Issue #630: pure geometric row hit-testing for a speech-bubble menu.
# Given an Array[Rect2] of row rectangles and a Vector2 point, resolves the
# index of the containing row, or -1. No scene tree, no UI.


func test_core_wiring_single_rect_hit():
	var rects: Array[Rect2] = [Rect2(0, 0, 100, 20)]
	assert_eq(BubbleRowHitTest.row_at(rects, Vector2(50, 10)), 0)


func test_multiple_rows_point_in_middle_row():
	var rects: Array[Rect2] = [
		Rect2(0, 0, 100, 20),
		Rect2(0, 20, 100, 20),
		Rect2(0, 40, 100, 20),
	]
	assert_eq(BubbleRowHitTest.row_at(rects, Vector2(10, 30)), 1)


func test_point_outside_all_rectangles_returns_minus_one():
	var rects: Array[Rect2] = [
		Rect2(0, 0, 100, 20),
		Rect2(0, 20, 100, 20),
		Rect2(0, 40, 100, 20),
	]
	assert_eq(BubbleRowHitTest.row_at(rects, Vector2(10, 100)), -1)


func test_empty_array_returns_minus_one():
	var rects: Array[Rect2] = []
	assert_eq(BubbleRowHitTest.row_at(rects, Vector2(10, 10)), -1)


func test_overlapping_rects_returns_first_match():
	var rects: Array[Rect2] = [
		Rect2(0, 0, 100, 50),
		Rect2(0, 0, 100, 50),
	]
	assert_eq(BubbleRowHitTest.row_at(rects, Vector2(10, 10)), 0, "first matching rect wins")
