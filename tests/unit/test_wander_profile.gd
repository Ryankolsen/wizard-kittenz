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


# ---------------------------------------------------------------------------
# PACER style (PRD #391 / slice #393) — wired to dog knight.
# ---------------------------------------------------------------------------

const _PACER_IDLE_SPEED: float = 20.0  # CHASE_SPEED 40 * pacer fraction 0.50
const _PACER_RADIUS: float = 64.0
const _PACER_CHANGE: float = 1.0
const _PACER_PAUSE: float = 0.6


func _pacer_params() -> Dictionary:
	return {
		"idle_speed": _PACER_IDLE_SPEED,
		"radius": _PACER_RADIUS,
		"change_cadence": _PACER_CHANGE,
		"pause_length": _PACER_PAUSE,
	}


func test_pacer_emits_non_zero_velocity_during_move_phase():
	# Core wiring: the pacer style produces a non-zero velocity during its
	# move phase. Driving enough ticks to cross at least one move phase ensures
	# we sample one — the essential "pacer moves" outcome.
	var wp := WanderProfile.new(_SEED)
	var saw_move := false
	for _i in range(200):
		var v := wp.desired_velocity(
			WanderProfile.Style.PACER, _pacer_params(),
			Vector2.ZERO, Vector2.ZERO, 0.05)
		if v.length() > 0.0:
			saw_move = true
			# When moving, magnitude should equal the configured idle_speed.
			assert_almost_eq(v.length(), _PACER_IDLE_SPEED, 0.0001,
				"pacer move-phase velocity magnitude should equal idle_speed")
			break
	assert_true(saw_move, "pacer should emit a non-zero velocity within 200 ticks")


func test_pacer_alternates_move_and_pause_with_changing_headings():
	# Drive the module across at least one full cycle. Assert both a near-zero
	# pause phase and a moving phase fire, that headings change between
	# consecutive move phases, and that the simulated position stays leashed.
	var wp := WanderProfile.new(_SEED)
	var anchor := Vector2.ZERO
	var pos := Vector2.ZERO
	var dt := 0.05
	var saw_pause := false
	var saw_move := false
	var move_headings: Array = []
	var last_heading := Vector2.ZERO
	for _i in range(600):
		var v := wp.desired_velocity(
			WanderProfile.Style.PACER, _pacer_params(), anchor, pos, dt)
		pos += v * dt
		# Tolerance of one full step (idle_speed * dt = 1.0 px) since the leash
		# pulls inward starting from the tick the position reaches the radius.
		assert_true(pos.length() <= _PACER_RADIUS + 1.5,
			"pacer position should stay leashed within the radius (got %f)" % pos.length())
		if v.length() == 0.0:
			saw_pause = true
			last_heading = Vector2.ZERO
		else:
			saw_move = true
			var heading := v.normalized()
			if last_heading == Vector2.ZERO:
				# A fresh move phase — capture its heading.
				move_headings.append(heading)
			last_heading = heading
	assert_true(saw_pause, "pacer should produce a zero-velocity pause phase")
	assert_true(saw_move, "pacer should produce a moving phase")
	assert_true(move_headings.size() >= 2,
		"pacer should produce at least two distinct move phases over the window")
	# Headings should change between consecutive move phases (not the same vector).
	var first: Vector2 = move_headings[0]
	var second: Vector2 = move_headings[1]
	assert_ne(first, second,
		"pacer should re-roll its heading between consecutive move phases")
