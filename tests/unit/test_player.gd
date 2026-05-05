extends GutTest

const SPEED := 60.0

func test_zero_input_yields_zero_velocity():
	var v := Player.compute_velocity(Vector2.ZERO, SPEED)
	assert_eq(v, Vector2.ZERO, "no input should produce no velocity")

func test_right_input_moves_right():
	var v := Player.compute_velocity(Vector2.RIGHT, SPEED)
	assert_eq(v, Vector2(SPEED, 0.0), "right input should move at +speed on x")

func test_up_input_moves_up():
	var v := Player.compute_velocity(Vector2.UP, SPEED)
	assert_eq(v, Vector2(0.0, -SPEED), "up input should move at -speed on y")

func test_diagonal_preserves_input_magnitude():
	var diag := Vector2(1, 1).normalized()
	var v := Player.compute_velocity(diag, SPEED)
	assert_almost_eq(v.length(), SPEED, 0.001, "normalized diagonal should not exceed speed")
