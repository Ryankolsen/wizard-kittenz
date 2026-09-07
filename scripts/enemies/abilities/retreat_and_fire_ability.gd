class_name RetreatAndFireAbility
extends EnemyAbility

# Retreat and fire archetype (PRD #518 / issue #537). Old Lady Pearl's other
# half: holds ~PREFERRED_RANGE from the player, backing away on melee entry
# and closing back in if the player disengages, with a deadband so it holds
# rather than oscillating right at the edge. Fires a knitting-needle
# EnemyProjectile every FIRE_INTERVAL seconds while at range. The player's
# counter is to corner it.
#
# This generalises the kiting logic CatnipDealerBehavior.desired_direction /
# HauntedSprayBottleBehavior.desired_direction already implement by hand —
# same range/deadband/flee math — but unlike those two (whose Enemy-side
# `_drive_*` hooks are no-op stubs, so the hand-rolled direction never
# actually drives motion in play) this archetype claims motion itself via
# `is_overriding_motion`/`drive_motion` so the kite is real in-game, not only
# in its own unit tests.
#
# No danger zone, same as SummonAddsAbility: the projectile is the tell, so
# firing is handled inline in `tick` rather than through the shared zone/
# wind-up pump, and `wants_to_fire` stays hard false.

const PREFERRED_RANGE: float = 140.0
const FLEE_RANGE: float = 50.0
const RANGE_DEADBAND: float = 10.0
const FIRE_INTERVAL: float = 2.2
const PROJECTILE_SPEED: float = 170.0
const PROJECTILE_RADIUS: float = 6.0
const PROJECTILE_COLOR: Color = Color(0.85, 0.8, 0.7, 1.0)
const PROJECTILE_MAX_RANGE: float = 360.0

# Variant null sentinel — Vector2 target once a fire is queued and the
# Enemy-side observer has not yet consumed the spawn request.
var pending_fire_target = null

var _fire_elapsed: float = 0.0
var _kiting: bool = false


# This archetype never drives the shared zone/wind-up pump — firing is
# entirely inline in `tick`, matching SummonAddsAbility.
func wants_to_fire() -> bool:
	return false


# Pure helper returning a unit-length direction vector (or Vector2.ZERO inside
# the deadband). Mirrors CatnipDealerBehavior.desired_direction: flee zone
# (≤FLEE_RANGE) and inside preferred range both read as "back away"; outside
# preferred range reads as "approach"; the deadband around PREFERRED_RANGE
# holds so the enemy doesn't hunt back and forth across the boundary.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	var dist := to_player.length()
	if dist == 0.0:
		return Vector2.RIGHT
	if dist <= FLEE_RANGE:
		return -to_player.normalized()
	if dist < PREFERRED_RANGE - RANGE_DEADBAND:
		return -to_player.normalized()
	if dist > PREFERRED_RANGE + RANGE_DEADBAND:
		return to_player.normalized()
	return Vector2.ZERO


# Claims motion whenever this ability is actively kiting (set each tick by
# `tick`), so the Enemy node's base chase/attack block steps aside and
# `drive_motion` below writes position directly — the archetype refuses melee
# outright rather than merely preferring range.
func is_overriding_motion() -> bool:
	return _kiting


func drive_motion(delta: float, enemy) -> void:
	if enemy == null:
		return
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D):
		return
	var move_speed: float = EnemyAIState.CHASE_SPEED
	var ms = enemy.get("move_speed")
	if ms != null:
		move_speed = float(ms)
	var dir := desired_direction(enemy.global_position, (player as Node2D).global_position)
	if dir == Vector2.ZERO:
		return
	enemy.global_position += dir * move_speed * delta


func tick(delta: float, enemy) -> void:
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		_kiting = false
		return
	# Aggro gate (issue #261 / PRD #518): an IDLE Pearl must neither kite nor
	# accrue fire cadence — matches the aggro gate every other archetype and
	# the pre-archetype mobs share.
	if not EnemyBehavior.is_aggroed(enemy):
		_kiting = false
		return
	_kiting = true
	_fire_elapsed += delta
	if enemy == null:
		return
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D):
		return
	if _fire_elapsed < FIRE_INTERVAL:
		return
	var player_node := player as Node2D
	var dist: float = enemy.global_position.distance_to(player_node.global_position)
	# Don't fire while inside the flee threshold — Pearl is busy retreating —
	# and gate by projectile range so a fire never leaves her with a
	# guaranteed miss.
	if dist <= FLEE_RANGE or dist > PROJECTILE_MAX_RANGE:
		return
	pending_fire_target = player_node.global_position
	_fire_elapsed = 0.0
