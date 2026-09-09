extends GutTest

# BeatLockedSlamAbility (PRD #518 / issue #579). DJ Dubstep's shockwave rings
# fire on a steady, fixed-tempo clock rather than a free-running cooldown, so
# the interval is learnable and does not drift over a long fight. Same
# _MockEnemy/_MockPlayer shape as test_enemy_behavior.gd and
# test_ground_slam_ability.gd (duplicated locally, same convention every
# archetype test file already follows), extended with a `data` HP pair so the
# enrage-tempo interaction (test group 5) has something to threshold against.

class _MockData:
	var hp: int = 10
	var max_hp: int = 10
	var attack: int = 4

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var move_speed: float = 100.0
	var data: _MockData = _MockData.new()
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


# --- 1. Core wiring -----------------------------------------------------------

func test_ring_zone_published_at_the_tempo_interval():
	var interval := 1.0
	var b := BeatLockedSlamAbility.new(interval, 0.6, 0.3, 0.1, 0.2, 0.1, 80.0, 20.0)
	var e := _MockEnemy.new()
	var step := 0.05
	var elapsed := 0.0
	while elapsed < interval + 0.2:
		b.tick(step, e)
		elapsed += step
		if b.wants_to_fire():
			b.begin(e)
			break
	assert_not_null(b.pending_zone, "a ring zone should have been published once the tempo interval elapsed")
	assert_eq(b.pending_zone.kind, DangerZoneShape.Kind.RING,
		"the beat-locked slam's telegraph must be a ring, not a disc/lane/tether")
	assert_almost_eq(elapsed, interval, 0.1,
		"the zone should publish right at the tempo interval, not sooner or later")


# --- 2. Steady tempo -----------------------------------------------------------

func test_gaps_between_consecutive_slams_are_equal():
	# A free-running cooldown that restarts only once a whole zone (windup +
	# commit + fade) finishes would make later gaps wider than earlier ones;
	# this is the failure this test exists to catch.
	var interval := 0.8
	var b := BeatLockedSlamAbility.new(interval, 0.5, 0.3, 0.1, 0.15, 0.05, 60.0, 15.0)
	var e := _MockEnemy.new()
	var step := 0.02
	var elapsed := 0.0
	var fire_times: Array = []
	while fire_times.size() < 5 and elapsed < 10.0:
		b.tick(step, e)
		elapsed += step
		if b.wants_to_fire():
			b.begin(e)
			fire_times.append(elapsed)
	assert_eq(fire_times.size(), 5, "sanity: five slams should have fired")
	for i in range(1, fire_times.size()):
		var gap: float = fire_times[i] - fire_times[i - 1]
		assert_almost_eq(gap, interval, 0.05,
			"the gap between consecutive slams must stay constant at the tempo interval")


# --- 3. No drift -----------------------------------------------------------------

func test_nth_slam_lands_at_n_times_the_interval():
	var interval := 0.5
	var b := BeatLockedSlamAbility.new(interval, 0.3, 0.3, 0.05, 0.1, 0.05, 50.0, 10.0)
	var e := _MockEnemy.new()
	var step := 0.02
	var elapsed := 0.0
	var fire_times: Array = []
	while fire_times.size() < 10 and elapsed < 10.0:
		b.tick(step, e)
		elapsed += step
		if b.wants_to_fire():
			b.begin(e)
			fire_times.append(elapsed)
	assert_eq(fire_times.size(), 10, "sanity: ten slams should have fired")
	for n in range(fire_times.size()):
		var expected: float = interval * float(n + 1)
		assert_almost_eq(fire_times[n], expected, 0.1,
			"the nth slam must land at n times the interval, so a long fight never drifts off-beat")


# --- 4. Fires through its own zone -------------------------------------------

func test_beat_clock_keeps_advancing_while_a_previous_zone_is_still_active():
	# Tempo interval deliberately shorter than the zone's own total lifetime
	# (windup + commit + fade), so the second beat comes due while the first
	# zone is still active. The base EnemyAbility clock only accrues cooldown
	# while NOT active (enemy_ability.gd's tick), which would freeze this
	# ability's clock for the zone's whole lifetime and then restart a fresh
	# interval from zero once it clears -- exactly the drift the PRD forbids.
	# With the fix, the clock keeps advancing through the active zone, so the
	# very next tick after the zone clears is already overdue and fires
	# immediately: the observed gap tracks the zone's own lifetime (the
	# limiting factor once it's longer than the tempo), not tempo + lifetime.
	var interval := 1.0
	var windup := 0.3
	var commit := 0.6
	var fade := 0.2
	var zone_total := windup + commit + fade  # 1.1s, longer than the 1.0s tempo
	var b := BeatLockedSlamAbility.new(interval, 0.8, 0.3, windup, commit, fade, 90.0, 20.0)
	var e := _MockEnemy.new()
	var step := 0.02
	var elapsed := 0.0
	var fire_times: Array = []
	while fire_times.size() < 2 and elapsed < 6.0:
		b.tick(step, e)
		elapsed += step
		if b.wants_to_fire():
			b.begin(e)
			fire_times.append(elapsed)
	assert_eq(fire_times.size(), 2, "sanity: two slams should have fired")
	var gap: float = fire_times[1] - fire_times[0]
	assert_almost_eq(gap, zone_total, 0.1,
		"the beat clock must keep advancing while its own zone is active, not pause for the zone's lifetime")


# --- 5. Enrage speeds the tempo ------------------------------------------------

func test_enrage_shortens_the_interval_and_stays_steady_afterwards():
	var interval := 2.0
	var enraged_interval := 1.2
	var hp_fraction := 0.3
	var b := BeatLockedSlamAbility.new(interval, enraged_interval, hp_fraction, 0.2, 0.3, 0.1, 90.0, 20.0)
	var e := _MockEnemy.new()
	e.data.hp = 10
	e.data.max_hp = 10
	var step := 0.05
	var elapsed := 0.0
	var fire_times: Array = []
	while fire_times.size() < 5 and elapsed < 20.0:
		b.tick(step, e)
		elapsed += step
		if b.wants_to_fire():
			b.begin(e)
			fire_times.append(elapsed)
			if fire_times.size() == 1:
				# Cross the enrage threshold right after the first (pre-enrage)
				# beat fires, so the very next gap already reflects the
				# shortened tempo.
				e.data.hp = 2
	assert_eq(fire_times.size(), 5, "sanity: five beats should have fired")
	var first_gap: float = fire_times[1] - fire_times[0]
	assert_almost_eq(first_gap, enraged_interval, 0.15,
		"the interval must shorten to the configured enraged tempo once HP crosses the threshold")
	for i in range(2, fire_times.size()):
		var gap: float = fire_times[i] - fire_times[i - 1]
		assert_almost_eq(gap, enraged_interval, 0.1,
			"the enraged tempo must stay steady across subsequent beats, not just the first one")


# --- 6. Escapable at the enraged tempo -----------------------------------------

func test_enraged_interval_leaves_room_to_clear_the_ring_on_foot():
	var b := BeatLockedSlamAbility.new(3.0, 2.2, 0.3, 0.4, 0.9, 0.2, 90.0, 20.0)
	var time_for_walker: float = b.max_radius() / 60.0
	assert_gt(b.enraged_interval(), b.windup_duration() + time_for_walker,
		"a 60 px/s walker must still be able to clear the ring before the next beat lands, even enraged")


# --- 7. Edge cases ----------------------------------------------------------------

func test_zero_or_negative_tempo_is_clamped_not_a_fire_storm():
	var b := BeatLockedSlamAbility.new(0.0, -1.0, 0.3, 0.05, 0.05, 0.05, 50.0, 10.0)
	var e := _MockEnemy.new()
	var fires := 0
	for _i in range(5):
		b.tick(0.001, e)
		if b.wants_to_fire():
			b.begin(e)
			fires += 1
	assert_lte(fires, 1, "a zero or negative tempo must be clamped to a sane minimum, not fire every frame")


func test_single_oversized_tick_fires_once_not_many_times():
	var b := BeatLockedSlamAbility.new(0.5, 0.3, 0.3, 0.05, 0.05, 0.05, 50.0, 10.0)
	var e := _MockEnemy.new()
	b.tick(10.0, e)  # one huge tick, far exceeding many intervals' worth of time
	var fires := 0
	if b.wants_to_fire():
		b.begin(e)
		fires += 1
	assert_eq(fires, 1, "a single oversized tick must only ever yield one fire opportunity, not several")


func test_idle_enemy_publishes_nothing():
	var b := BeatLockedSlamAbility.new(0.3, 0.2, 0.3, 0.05, 0.1, 0.05, 60.0, 15.0)
	var e := _MockEnemy.new()
	e.state = 0  # EnemyAIState.State.IDLE
	for _i in range(10):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "an IDLE enemy must not publish a beat-locked ring zone")


func test_null_enemy_does_not_crash():
	var b := BeatLockedSlamAbility.new(0.3, 0.2, 0.3, 0.05, 0.1, 0.05, 60.0, 15.0)
	b.tick(1.0, null)
	assert_false(b.wants_to_fire(), "a null enemy must not crash and must never accrue toward firing")
