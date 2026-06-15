extends GutTest

# WanderProfile (PRD #391 / slice #392) — pure RefCounted idle-wander module.
# Tests construct the module directly with a fixed seed, no scene tree, matching
# the pattern in test_enemy_behavior.gd.

const _IDLE_SPEED: float = 4.0  # CHASE_SPEED 40 * stationary-ish fraction 0.10
const _RADIUS: float = 24.0
const _CHANGE: float = 0.6
const _PAUSE: float = 1.5
const _SEED: int = 4242

func _params() -> Dictionary:
	return {
		"idle_speed": _IDLE_SPEED,
		"radius": _RADIUS,
		"change_cadence": _CHANGE,
		"pause_length": _PAUSE,
	}


func test_stationary_ish_yields_small_non_negative_velocity():
	# Core wiring: given the stationary-ish style at the anchor, the module
	# returns a velocity whose magnitude is small (bounded by idle_speed) and
	# non-negative — the "it produces an idle velocity" outcome.
	var wp := WanderProfile.new(_SEED)
	var v := wp.desired_velocity(
		WanderProfile.Style.STATIONARY_ISH, _params(),
		Vector2.ZERO, Vector2.ZERO, 0.05)
	assert_true(v.length() >= 0.0, "velocity magnitude should be non-negative")
	assert_true(v.length() <= _IDLE_SPEED + 0.0001,
		"velocity should be bounded by idle_speed")


func test_stationary_ish_stays_leashed_within_radius():
	# Leashing: simulate position over many ticks from a fixed seed and assert
	# the simulated position never strays outside the configured radius.
	var wp := WanderProfile.new(_SEED)
	var anchor := Vector2.ZERO
	var pos := Vector2.ZERO
	var dt := 0.05
	for _i in range(2000):
		var v := wp.desired_velocity(
			WanderProfile.Style.STATIONARY_ISH, _params(), anchor, pos, dt)
		pos += v * dt
		assert_true(pos.length() <= _RADIUS + 0.5,
			"wander should stay leashed within the radius (got %f)" % pos.length())


func test_stationary_ish_is_deterministic_under_fixed_seed():
	# Determinism: two profiles with the same seed and the same input stream
	# produce identical velocity sequences.
	var wp_a := WanderProfile.new(_SEED)
	var wp_b := WanderProfile.new(_SEED)
	var anchor := Vector2.ZERO
	var pos := Vector2.ZERO
	var dt := 0.05
	for _i in range(200):
		var va := wp_a.desired_velocity(
			WanderProfile.Style.STATIONARY_ISH, _params(), anchor, pos, dt)
		var vb := wp_b.desired_velocity(
			WanderProfile.Style.STATIONARY_ISH, _params(), anchor, pos, dt)
		assert_eq(va, vb, "same seed + inputs should produce identical velocities")
		pos += va * dt


func test_stationary_ish_is_not_stuck_at_zero_forever():
	# The 20% shuffle branch must actually fire over time so the spray bottle
	# visibly twitches — otherwise the module degrades to "stand still".
	var wp := WanderProfile.new(_SEED)
	var any_nonzero := false
	for _i in range(500):
		var v := wp.desired_velocity(
			WanderProfile.Style.STATIONARY_ISH, _params(),
			Vector2.ZERO, Vector2.ZERO, 0.05)
		if v.length() > 0.0:
			any_nonzero = true
			break
	assert_true(any_nonzero,
		"stationary-ish should emit at least one non-zero velocity within 500 ticks")
