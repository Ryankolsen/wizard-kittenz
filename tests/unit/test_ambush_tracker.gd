extends GutTest

# Ambush tracker (PRD #518 / issue #536). Pure blind-arc + scare-charge
# accounting for Sir Pickleton's ambush archetype. Same _MockEnemy-style mock
# pattern as tests/unit/test_enemy_behavior.gd — small plain-data stand-ins
# rather than real scene nodes — with a mock player exposing global_position
# and a facing vector, matching the shape AmbushAbility reads off the real
# Player/Enemy nodes (player.data.facing, enemy.global_position).

class _MockPlayer:
	var global_position: Vector2 = Vector2.ZERO
	var facing: Vector2 = Vector2.DOWN

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO


# --- 7. Blind arc -----------------------------------------------------------

func test_enemy_behind_facing_is_in_blind_arc_enemy_in_front_is_not():
	var player := _MockPlayer.new()
	player.global_position = Vector2.ZERO
	player.facing = Vector2.RIGHT
	var behind := _MockEnemy.new()
	behind.global_position = Vector2(-50.0, 0.0)
	assert_true(
		AmbushTracker.is_in_blind_arc(player.global_position, player.facing, behind.global_position),
		"an enemy directly behind the player's facing should be inside the blind arc")
	var front := _MockEnemy.new()
	front.global_position = Vector2(50.0, 0.0)
	assert_false(
		AmbushTracker.is_in_blind_arc(player.global_position, player.facing, front.global_position),
		"an enemy directly in front of the player's facing should not be inside the blind arc")


# --- 8. Charge accrual -------------------------------------------------------

func test_charge_rises_while_behind_and_drains_rather_than_pauses_once_faced():
	var tracker := AmbushTracker.new()
	var player := _MockPlayer.new()
	player.facing = Vector2.RIGHT
	var enemy := _MockEnemy.new()
	enemy.global_position = Vector2(-50.0, 0.0)  # behind the player
	for _i in range(5):
		tracker.tick(0.2, player.global_position, player.facing, enemy.global_position)
	var charge_while_unseen := tracker.charge
	assert_gt(charge_while_unseen, 0.0, "scare charge should rise while the enemy sits in the blind arc")
	enemy.global_position = Vector2(50.0, 0.0)  # player is now facing it
	tracker.tick(0.2, player.global_position, player.facing, enemy.global_position)
	assert_lt(tracker.charge, charge_while_unseen,
		"scare charge should drain, not merely pause, once the player faces the enemy")


# --- 9. Scare gate -----------------------------------------------------------

func test_scare_cannot_fire_while_player_faces_the_enemy_even_at_max_charge():
	var tracker := AmbushTracker.new()
	tracker.charge = AmbushTracker.MAX_CHARGE
	var player := _MockPlayer.new()
	player.facing = Vector2.RIGHT
	var enemy := _MockEnemy.new()
	enemy.global_position = Vector2(50.0, 0.0)  # in front — player is looking at it
	assert_false(
		tracker.can_scare(player.global_position, player.facing, enemy.global_position),
		"the scare must not fire while the player faces the enemy even with charge at maximum")


# --- 10. Chain-lock prevention ------------------------------------------------

func test_cooldown_after_a_landed_scare_blocks_a_second_scare_before_it_elapses():
	var tracker := AmbushTracker.new()
	var player := _MockPlayer.new()
	player.facing = Vector2.RIGHT
	var enemy := _MockEnemy.new()
	enemy.global_position = Vector2(-50.0, 0.0)  # behind
	for _i in range(10):
		tracker.tick(0.2, player.global_position, player.facing, enemy.global_position)
	assert_true(tracker.can_scare(player.global_position, player.facing, enemy.global_position),
		"precondition: charge should be full and the enemy still unseen")
	tracker.trigger_scare()
	# Drive enough ticks to fully refill charge — well short of the long
	# post-scare cooldown — and assert a second scare still cannot fire.
	for _i in range(10):
		tracker.tick(0.2, player.global_position, player.facing, enemy.global_position)
	assert_eq(tracker.charge, AmbushTracker.MAX_CHARGE, "precondition: charge refilled")
	assert_false(tracker.can_scare(player.global_position, player.facing, enemy.global_position),
		"a second scare must not be permitted before the post-scare cooldown elapses")


# --- 11. Edge cases -----------------------------------------------------------

func test_null_player_position_is_not_in_the_blind_arc():
	var enemy := _MockEnemy.new()
	enemy.global_position = Vector2(-50.0, 0.0)
	assert_false(AmbushTracker.is_in_blind_arc(null, Vector2.RIGHT, enemy.global_position),
		"a null player position must not crash and must not count as blind")

func test_zero_length_facing_vector_is_not_in_the_blind_arc():
	var enemy := _MockEnemy.new()
	enemy.global_position = Vector2(-50.0, 0.0)
	assert_false(AmbushTracker.is_in_blind_arc(Vector2.ZERO, Vector2.ZERO, enemy.global_position),
		"a zero-length facing vector must not crash and must not count as blind")

func test_enemy_exactly_perpendicular_to_facing_sits_on_the_boundary():
	var player := _MockPlayer.new()
	player.facing = Vector2.RIGHT
	var perpendicular := _MockEnemy.new()
	perpendicular.global_position = Vector2(0.0, 50.0)
	assert_false(
		AmbushTracker.is_in_blind_arc(player.global_position, player.facing, perpendicular.global_position),
		"an enemy exactly perpendicular to facing is the arc boundary and is treated as seen, not blind")
