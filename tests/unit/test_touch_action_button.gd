extends GutTest

# Tests for the TouchActionButton hit-rect math added for #25. The
# button itself drives Input.action_press(action_name) on touch down
# and Input.action_release on touch up — both of which are
# integration-tested at the (real device) QA gate. What's unit-testable
# here is the point-in-rect check that decides whether a given touch
# hits the button at all.

func test_is_inside_rect_point_inside_returns_true():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	# Center of the rect (428, 224) — comfortably inside.
	assert_true(TouchActionButton.is_inside_rect(Vector2(428, 224), origin, sz))

func test_is_inside_rect_point_at_top_left_corner_inclusive():
	# Touch lands exactly on the top-left pixel: should hit. Otherwise a
	# thumb tap on the visible border feels like it's outside the button.
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_true(TouchActionButton.is_inside_rect(origin, origin, sz))

func test_is_inside_rect_point_at_bottom_right_corner_inclusive():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_true(TouchActionButton.is_inside_rect(
		Vector2(origin.x + sz.x, origin.y + sz.y), origin, sz))

func test_is_inside_rect_point_to_the_left_returns_false():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_false(TouchActionButton.is_inside_rect(Vector2(395, 224), origin, sz))

func test_is_inside_rect_point_above_returns_false():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_false(TouchActionButton.is_inside_rect(Vector2(428, 195), origin, sz))

func test_is_inside_rect_point_to_the_right_returns_false():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_false(TouchActionButton.is_inside_rect(
		Vector2(origin.x + sz.x + 1, 224), origin, sz))

func test_is_inside_rect_point_below_returns_false():
	var origin := Vector2(396, 196)
	var sz := Vector2(64, 56)
	assert_false(TouchActionButton.is_inside_rect(
		Vector2(428, origin.y + sz.y + 1), origin, sz))

# Smoke: the script can be instantiated and exposes the configured
# action_name property. Guards against a future rename that breaks the
# .tscn binding silently.
func test_script_has_action_name_property():
	var btn := TouchActionButton.new()
	btn.action_name = &"attack"
	assert_eq(btn.action_name, &"attack")
	btn.free()

func test_script_default_action_name_is_empty():
	# Buttons without a configured action_name must no-op (the press
	# handler short-circuits when action_name is empty). This prevents
	# a misconfigured scene from spamming Input with empty action calls.
	var btn := TouchActionButton.new()
	assert_eq(btn.action_name, &"")
	btn.free()
