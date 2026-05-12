extends GutTest

# Tests for the analog virtual joystick added for #25's long-term
# Android-touch fix. The keyboard-only InputMap is unplayable on a
# real touch device; this overlay drives the same move_* actions via
# Input.action_press(strength), so Player's existing
# Input.get_vector("move_left", "move_right", "move_up", "move_down")
# call site keeps working unchanged.
#
# The four pieces of joystick math are exposed as static helpers so we
# don't need to boot a SceneTree, stub Input, or emit fake touch events
# to exercise them.

const BASE := 28.0
const DEADZONE := 0.2

# --- compute_clamped_offset ------------------------------------------------

func test_compute_clamped_offset_within_radius_unchanged():
	var center := Vector2(50, 200)
	var touch := Vector2(60, 195)
	var offset := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	assert_eq(offset, Vector2(10, -5),
		"a touch inside the base radius should be reported as a raw offset")

func test_compute_clamped_offset_outside_clamped_to_radius():
	var center := Vector2(50, 200)
	# Touch is 100px to the right — way outside a 28px base.
	var touch := Vector2(150, 200)
	var offset := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	assert_almost_eq(offset.length(), BASE, 0.001,
		"a touch outside the base radius should clamp to the radius")
	assert_almost_eq(offset.x, BASE, 0.001, "clamped offset preserves direction (x)")
	assert_almost_eq(offset.y, 0.0, 0.001, "clamped offset preserves direction (y)")

func test_compute_clamped_offset_diagonal_clamped_preserves_angle():
	var center := Vector2.ZERO
	var touch := Vector2(100, 100)  # 45 degrees, ~141px out
	var offset := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	assert_almost_eq(offset.length(), BASE, 0.001)
	assert_almost_eq(offset.x, offset.y, 0.001,
		"a 45-degree input keeps a 45-degree clamped offset")

func test_compute_clamped_offset_at_center_is_zero():
	var center := Vector2(50, 200)
	var offset := VirtualJoystick.compute_clamped_offset(center, center, BASE)
	assert_eq(offset, Vector2.ZERO,
		"a touch exactly at the center reports zero offset (no NaN)")

# --- compute_direction (deadzone + normalize) -----------------------------

func test_compute_direction_zero_within_deadzone():
	# At deadzone_fraction=0.2, BASE=28, deadzone = 5.6px.
	var offset := Vector2(3, 0)  # well inside the deadzone
	var dir := VirtualJoystick.compute_direction(offset, BASE, DEADZONE)
	assert_eq(dir, Vector2.ZERO,
		"a small offset inside the deadzone should not drive movement")

func test_compute_direction_outside_deadzone_normalized_by_radius():
	# Offset = BASE/2 = 14, deadzone = 5.6 → past the deadzone.
	# Direction = offset / BASE = 0.5.
	var dir := VirtualJoystick.compute_direction(Vector2(BASE * 0.5, 0), BASE, DEADZONE)
	assert_almost_eq(dir.x, 0.5, 0.001,
		"direction magnitude = offset / base_radius outside the deadzone")
	assert_almost_eq(dir.y, 0.0, 0.001)

func test_compute_direction_at_max_offset_is_unit_vector():
	var dir := VirtualJoystick.compute_direction(Vector2(BASE, 0), BASE, DEADZONE)
	assert_almost_eq(dir.x, 1.0, 0.001,
		"a fully-extended joystick should report direction magnitude 1.0")

func test_compute_direction_zero_radius_safe():
	# Defensive: a zero base_radius could divide by zero. The function
	# returns ZERO rather than crashing the per-frame _process.
	var dir := VirtualJoystick.compute_direction(Vector2(10, 10), 0.0, DEADZONE)
	assert_eq(dir, Vector2.ZERO,
		"zero base_radius must not divide by zero; treat as no input")

# --- compute_action_strengths --------------------------------------------

func test_compute_action_strengths_right_only_fills_right():
	var s := VirtualJoystick.compute_action_strengths(Vector2(0.7, 0.0))
	assert_almost_eq(float(s["move_right"]), 0.7, 0.001)
	assert_eq(float(s["move_left"]), 0.0)
	assert_eq(float(s["move_up"]), 0.0)
	assert_eq(float(s["move_down"]), 0.0)

func test_compute_action_strengths_left_only_fills_left():
	var s := VirtualJoystick.compute_action_strengths(Vector2(-0.5, 0.0))
	assert_almost_eq(float(s["move_left"]), 0.5, 0.001)
	assert_eq(float(s["move_right"]), 0.0)

func test_compute_action_strengths_up_only_fills_up():
	# Godot's y axis is downward, so a negative y direction = "up".
	var s := VirtualJoystick.compute_action_strengths(Vector2(0.0, -0.8))
	assert_almost_eq(float(s["move_up"]), 0.8, 0.001)
	assert_eq(float(s["move_down"]), 0.0)

func test_compute_action_strengths_down_only_fills_down():
	var s := VirtualJoystick.compute_action_strengths(Vector2(0.0, 0.6))
	assert_almost_eq(float(s["move_down"]), 0.6, 0.001)
	assert_eq(float(s["move_up"]), 0.0)

func test_compute_action_strengths_diagonal_fills_two_axes():
	var s := VirtualJoystick.compute_action_strengths(Vector2(0.6, -0.4))
	assert_almost_eq(float(s["move_right"]), 0.6, 0.001)
	assert_almost_eq(float(s["move_up"]), 0.4, 0.001)
	assert_eq(float(s["move_left"]), 0.0)
	assert_eq(float(s["move_down"]), 0.0)

func test_compute_action_strengths_zero_input_all_zero():
	var s := VirtualJoystick.compute_action_strengths(Vector2.ZERO)
	assert_eq(float(s["move_left"]), 0.0)
	assert_eq(float(s["move_right"]), 0.0)
	assert_eq(float(s["move_up"]), 0.0)
	assert_eq(float(s["move_down"]), 0.0)

# --- End-to-end pipeline: touch -> action strengths ----------------------

# These tests pin the full pipeline (touch position -> clamp -> deadzone
# -> per-action strength) so a future tweak to one helper doesn't break
# the contract Player relies on through Input.get_vector.

func test_pipeline_right_edge_touch_drives_move_right_only():
	var center := Vector2(50, 200)
	var touch := Vector2(78, 200)  # exactly BASE px right of center
	var off := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	var dir := VirtualJoystick.compute_direction(off, BASE, DEADZONE)
	var s := VirtualJoystick.compute_action_strengths(dir)
	assert_almost_eq(float(s["move_right"]), 1.0, 0.001)
	assert_eq(float(s["move_left"]), 0.0)
	assert_eq(float(s["move_up"]), 0.0)
	assert_eq(float(s["move_down"]), 0.0)

func test_pipeline_dead_center_yields_no_strength():
	# Confirms a stationary thumb at base center never fires any action,
	# even with the deadzone disabled (offset is zero).
	var center := Vector2(50, 200)
	var off := VirtualJoystick.compute_clamped_offset(center, center, BASE)
	var dir := VirtualJoystick.compute_direction(off, BASE, DEADZONE)
	var s := VirtualJoystick.compute_action_strengths(dir)
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		assert_eq(float(s[action]), 0.0,
			"%s should be 0 when thumb is at base center" % action)

func test_pipeline_upper_left_touch_drives_left_and_up():
	# 45-degree push toward upper-left at max offset: equal strength on
	# move_left and move_up, zero on move_right/move_down.
	var center := Vector2.ZERO
	var touch := Vector2(-100, -100)  # clamps to (-28*√0.5, -28*√0.5)
	var off := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	var dir := VirtualJoystick.compute_direction(off, BASE, DEADZONE)
	var s := VirtualJoystick.compute_action_strengths(dir)
	assert_almost_eq(float(s["move_left"]), float(s["move_up"]), 0.001,
		"diagonal upper-left should drive left and up at equal strength")
	assert_gt(float(s["move_left"]), 0.5, "diagonal strength should be substantial")
	assert_eq(float(s["move_right"]), 0.0)
	assert_eq(float(s["move_down"]), 0.0)

func test_pipeline_tiny_jiggle_inside_deadzone_yields_no_strength():
	# Player rests their thumb on the joystick — micro-jitter should
	# never produce phantom movement.
	var center := Vector2(50, 200)
	var touch := Vector2(52, 199)  # 2.24 px out, well inside 5.6 deadzone
	var off := VirtualJoystick.compute_clamped_offset(touch, center, BASE)
	var dir := VirtualJoystick.compute_direction(off, BASE, DEADZONE)
	var s := VirtualJoystick.compute_action_strengths(dir)
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		assert_eq(float(s[action]), 0.0,
			"deadzone jiggle should not move (got %s=%s)" % [action, s[action]])
