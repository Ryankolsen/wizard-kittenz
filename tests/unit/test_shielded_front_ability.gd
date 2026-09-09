extends GutTest

# ShieldedFrontAbility (PRD #518 / issue #578). Completes The Bouncer: he
# cannot be hurt from the front, so the fight is about getting behind him.
# Same _MockEnemy/_MockPlayer shape as test_enemy_behavior.gd, extended with
# the `data.enemy_id` field test_zone_denial_ability.gd's `_seeded` mocks use,
# since the idle-facing fallback seeds off the enemy's stable spawn id.

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var data: _MockData = _MockData.new()
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


func _seeded(enemy_id: String) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.data.enemy_id = enemy_id
	return e


# --- 1. Core wiring ----------------------------------------------------------

func test_hit_from_inside_shield_is_reduced():
	var b := ShieldedFrontAbility.new(75.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e0")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var front_pos: Vector2 = e.global_position + Vector2.RIGHT * 100.0
	var dealt := b.reduce_damage(e, front_pos, 10)
	assert_lt(dealt, 10, "a hit landing inside the frontal shield should be reduced")


# --- 2. Behind is unreduced ---------------------------------------------------

func test_hit_from_behind_is_unreduced():
	var b := ShieldedFrontAbility.new(75.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e1")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var behind_pos: Vector2 = e.global_position + Vector2.LEFT * 100.0
	var dealt := b.reduce_damage(e, behind_pos, 10)
	assert_eq(dealt, 10, "a hit landing outside the frontal shield must take full damage")


# --- 3. Zone boundary ---------------------------------------------------------

func test_boundary_is_inclusive_at_the_half_angle():
	# Facing +X, half-angle 30 degrees. Boundary convention: inclusive, same
	# as every DangerZoneShape edge (`<=`), so a hit exactly on the line still
	# counts as caught by the shield.
	var b := ShieldedFrontAbility.new(30.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e2")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var just_inside := e.global_position + Vector2(cos(deg_to_rad(29.0)), sin(deg_to_rad(29.0))) * 100.0
	var just_outside := e.global_position + Vector2(cos(deg_to_rad(31.0)), sin(deg_to_rad(31.0))) * 100.0
	var on_boundary := e.global_position + Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 100.0
	assert_lt(b.reduce_damage(e, just_inside, 10), 10, "just inside the half-angle should be reduced")
	assert_eq(b.reduce_damage(e, just_outside, 10), 10, "just outside the half-angle should be unreduced")
	assert_lt(b.reduce_damage(e, on_boundary, 10), 10, "exactly on the boundary resolves inclusive (reduced)")


# --- 4. Never zero -------------------------------------------------------------

func test_reduction_never_reaches_zero():
	var b := ShieldedFrontAbility.new(75.0, 1.0, 1, 0.5)  # max reduction fraction
	var e := _seeded("f7-r1-e3")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var front_pos: Vector2 = e.global_position + Vector2.RIGHT * 100.0
	assert_gt(b.reduce_damage(e, front_pos, 50), 0, "even at maximum reduction a hit must deal damage")
	assert_eq(b.reduce_damage(e, front_pos, 1), 1, "a 1-damage hit through the shield must still deal 1")


# --- 5. Facing source ----------------------------------------------------------

func test_facing_tracks_movement_not_target():
	var b := ShieldedFrontAbility.new()
	var e := _seeded("f7-r1-e4")
	var target := _MockPlayer.new()
	target.global_position = Vector2(0.0, 100.0)  # straight down from the enemy
	e._player_ref = target
	e.velocity = Vector2(1.0, 0.0)  # moving straight right, away from the target
	b.resample_facing(e)
	assert_almost_eq(b.facing().x, 1.0, 0.0001)
	assert_almost_eq(b.facing().y, 0.0, 0.0001)
	assert_false(b.facing().is_equal_approx(Vector2.DOWN),
		"facing must not equal the direction toward the per-client target")


func test_idle_facing_does_not_track_a_moving_target():
	var b := ShieldedFrontAbility.new()
	var e := _seeded("f7-r1-e5")
	var target := _MockPlayer.new()
	target.global_position = Vector2(100.0, 0.0)
	e._player_ref = target
	e.velocity = Vector2.ZERO  # idle
	b.resample_facing(e)
	var first := b.facing()
	target.global_position = Vector2(-100.0, 250.0)  # target moves elsewhere entirely
	b.resample_facing(e)
	var second := b.facing()
	assert_eq(first, second,
		"an idle enemy's facing must not re-derive from a target that moved")


# --- 6. Both damage paths -------------------------------------------------------

func test_reduction_applies_identically_to_contact_and_ability_damage():
	# There is exactly one reduction function; both the contact-damage caller
	# and the ability-damage caller in Enemy's shared take-damage tail route
	# through it identically, so a "contact" hit and an "ability" hit of the
	# same raw amount from the same position resolve to the same result.
	var b := ShieldedFrontAbility.new(75.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e6")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var front_pos: Vector2 = e.global_position + Vector2.RIGHT * 100.0
	var contact_dealt := b.reduce_damage(e, front_pos, 20)
	var ability_dealt := b.reduce_damage(e, front_pos, 20)
	assert_eq(contact_dealt, ability_dealt,
		"the same raw hit from the same position must reduce identically regardless of delivery path")
	assert_lt(contact_dealt, 20)


# --- 7. Edge cases ---------------------------------------------------------------

func test_attacker_exactly_at_enemy_position_produces_no_nan():
	var b := ShieldedFrontAbility.new()
	var e := _seeded("f7-r1-e7")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var dealt := b.reduce_damage(e, e.global_position, 10)
	assert_false(is_nan(float(dealt)), "a coincident attacker must not produce NaN")


func test_zero_width_zone_only_catches_exact_facing_line():
	var b := ShieldedFrontAbility.new(0.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e8")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var on_axis := e.global_position + Vector2.RIGHT * 100.0
	var off_axis := e.global_position + Vector2(cos(deg_to_rad(1.0)), sin(deg_to_rad(1.0))) * 100.0
	assert_lt(b.reduce_damage(e, on_axis, 10), 10, "a zero-width zone still catches the exact facing line")
	assert_eq(b.reduce_damage(e, off_axis, 10), 10, "a zero-width zone excludes anything off-axis")


func test_zone_at_or_above_360_degrees_catches_everything():
	var b := ShieldedFrontAbility.new(360.0, 0.7, 1, 0.5)
	var e := _seeded("f7-r1-e9")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var behind_pos: Vector2 = e.global_position + Vector2.LEFT * 100.0
	assert_lt(b.reduce_damage(e, behind_pos, 10), 10,
		"a >=360-degree shield reduces a hit from every direction, including behind")


func test_null_attacker_position_does_not_crash_and_is_unreduced():
	var b := ShieldedFrontAbility.new()
	var e := _seeded("f7-r1-e10")
	e.velocity = Vector2.RIGHT
	b.resample_facing(e)
	var dealt := b.reduce_damage(e, null, 10)
	assert_eq(dealt, 10, "a null attacker position cannot be resolved as inside the shield, so it is unreduced")


# --- Integration: Enemy.apply_shield_reduction is the real convergence point --

# A unit test that only calls ShieldedFrontAbility.reduce_damage directly (as
# every test above does) proves the archetype's own math is right but cannot
# tell whether any real damage-dealing call site actually reaches it. This
# test goes through the real Enemy node instead, built the same way The
# Bouncer is built in production (EnemyBehavior.for_data via Enemy._ready,
# which composes his loadout through AbilityLoadout) — the same shape
# test_spell_damage_floating_text.gd uses for its Enemy fixtures — so a
# regression where the hook exists but nothing calls it (or calls it from
# only one of the three damage-dealing paths) fails here even though the
# archetype's own math is untouched.
func test_enemy_apply_shield_reduction_reduces_a_hit_from_the_front():
	var wrapper := Node2D.new()
	add_child_autofree(wrapper)
	var enemy := Enemy.new()
	enemy.data = EnemyData.make_new(EnemyData.EnemyKind.THE_BOUNCER)
	enemy.data.is_boss = true
	enemy.global_position = Vector2.ZERO
	wrapper.add_child(enemy)
	# ShieldedFrontAbility's facing defaults to Vector2.RIGHT until its first
	# resample (no tick has run yet on a freshly-built enemy), so a hit from
	# +X is deterministically "in front" without needing to drive ticks here.
	var front_pos := enemy.global_position + Vector2.RIGHT * 100.0
	var dealt := enemy.apply_shield_reduction(20, front_pos)
	assert_lt(dealt, 20,
		"Enemy.apply_shield_reduction must actually reduce a hit landing in front of The Bouncer")


func test_enemy_apply_shield_reduction_is_a_no_op_for_kinds_without_the_ability():
	var wrapper := Node2D.new()
	add_child_autofree(wrapper)
	var enemy := Enemy.new()
	enemy.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	wrapper.add_child(enemy)
	var dealt := enemy.apply_shield_reduction(20, enemy.global_position + Vector2.RIGHT * 100.0)
	assert_eq(dealt, 20, "a kind without ShieldedFrontAbility in its loadout must never reduce damage")
