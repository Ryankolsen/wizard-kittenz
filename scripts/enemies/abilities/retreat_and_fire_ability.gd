class_name RetreatAndFireAbility
extends EnemyAbility

# Retreat and fire archetype (PRD #518 / issue #537). Old Lady Pearl's other
# half: holds ~preferred range from the player, backing away on melee entry
# and closing back in if the player disengages, with a deadband so it holds
# rather than oscillating right at the edge. Fires an EnemyProjectile every
# fire interval while at range. The player's counter is to corner it.
#
# This generalises the kiting logic CatnipDealerBehavior.desired_direction /
# HauntedSprayBottleBehavior.desired_direction already implement by hand —
# same range/deadband/flee math — but unlike those two (whose Enemy-side
# `_drive_*` hooks are no-op stubs, so the hand-rolled direction never
# actually drives motion in play) this archetype claims motion itself via
# `is_overriding_motion`/`drive_motion` so the kite is real in-game, not only
# in its own unit tests.
#
# Every tuning value is a constructor parameter, defaulted to Old Lady Pearl's
# original constants below (issue #582 amendment). A caller that passes
# nothing gets Pearl's exact pre-#582 behavior: no danger zone (the projectile
# is the tell, same as SummonAddsAbility — firing is handled inline in `tick`
# and `wants_to_fire` stays hard false) because the telegraph flag also
# defaults to false. Passing `telegraph = true` (the Catnip Dealer's opt-in)
# switches firing onto the shared zone/wind-up pump instead: the throw
# publishes a locked-lane danger zone in the same amber-to-red vocabulary
# every other archetype draws, and the projectile is only requested once that
# zone reaches its commit phase, at the exact point the zone was aimed.

const PREFERRED_RANGE: float = 140.0
const FLEE_RANGE: float = 50.0
const RANGE_DEADBAND: float = 10.0
const FIRE_INTERVAL: float = 2.2
const PROJECTILE_SPEED: float = 170.0
const PROJECTILE_RADIUS: float = 6.0
const PROJECTILE_COLOR: Color = Color(0.85, 0.8, 0.7, 1.0)
const PROJECTILE_MAX_RANGE: float = 360.0

# Telegraph tuning for the opt-in wind-up path. Not exposed as constructor
# parameters — the issue asks only for a flag, not per-caller telegraph
# timing — but broken out as named consts rather than inline literals so a
# future archetype tweak has one place to land.
const TELEGRAPH_WINDUP_DURATION: float = 0.5
const TELEGRAPH_COMMIT_DURATION: float = 0.15
const TELEGRAPH_FADE_DURATION: float = 0.2
const TELEGRAPH_LANE_WIDTH: float = 20.0

# Variant null sentinel — Vector2 target once a fire is queued and the
# Enemy-side observer has not yet consumed the spawn request.
var pending_fire_target = null

var _preferred_range: float
var _flee_range: float
var _range_deadband: float
var _fire_interval: float
var _projectile_speed: float
var _projectile_radius: float
var _projectile_color: Color
var _projectile_max_range: float
var _telegraph: bool

var _fire_elapsed: float = 0.0
var _kiting: bool = false


func _init(
	preferred_range: float = PREFERRED_RANGE,
	flee_range: float = FLEE_RANGE,
	range_deadband: float = RANGE_DEADBAND,
	fire_interval: float = FIRE_INTERVAL,
	projectile_speed: float = PROJECTILE_SPEED,
	projectile_radius: float = PROJECTILE_RADIUS,
	projectile_color: Color = PROJECTILE_COLOR,
	projectile_max_range: float = PROJECTILE_MAX_RANGE,
	telegraph: bool = false
) -> void:
	_preferred_range = preferred_range
	_flee_range = flee_range
	_range_deadband = range_deadband
	_fire_interval = fire_interval
	_projectile_speed = projectile_speed
	_projectile_radius = projectile_radius
	_projectile_color = projectile_color
	_projectile_max_range = projectile_max_range
	_telegraph = telegraph


# --- Tuning accessors, so callers/tests read the resolved values rather than
# reaching past the constructor into private fields. ---

func preferred_range() -> float:
	return _preferred_range

func flee_range() -> float:
	return _flee_range

func range_deadband() -> float:
	return _range_deadband

func fire_interval() -> float:
	return _fire_interval

func projectile_speed() -> float:
	return _projectile_speed

func projectile_radius() -> float:
	return _projectile_radius

func projectile_color() -> Color:
	return _projectile_color

func projectile_max_range() -> float:
	return _projectile_max_range

func telegraph_enabled() -> bool:
	return _telegraph


# cooldown() is the fire cadence for the telegraph path's zone/wind-up pump
# (wants_to_fire below); the no-telegraph path times itself off _fire_elapsed
# directly, matching the pre-#582 inline behavior exactly.
func cooldown() -> float:
	return _fire_interval

func windup_duration() -> float:
	return TELEGRAPH_WINDUP_DURATION

func commit_duration() -> float:
	return TELEGRAPH_COMMIT_DURATION

func fade_duration() -> float:
	return TELEGRAPH_FADE_DURATION


# Only the telegraph path ever drives the shared zone/wind-up pump. With the
# flag left false this stays hard false, same as before #582: the projectile
# is the tell, so firing is handled inline in `tick`.
func wants_to_fire() -> bool:
	if not _telegraph:
		return false
	return not is_active() and _cooldown_elapsed >= cooldown()


# Pure helper returning a unit-length direction vector (or Vector2.ZERO inside
# the deadband). Mirrors CatnipDealerBehavior.desired_direction: flee zone
# (≤flee_range) and inside preferred range both read as "back away"; outside
# preferred range reads as "approach"; the deadband around preferred_range
# holds so the enemy doesn't hunt back and forth across the boundary.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	var dist := to_player.length()
	if dist == 0.0:
		return Vector2.RIGHT
	if dist <= _flee_range:
		return -to_player.normalized()
	if dist < _preferred_range - _range_deadband:
		return -to_player.normalized()
	if dist > _preferred_range + _range_deadband:
		return to_player.normalized()
	return Vector2.ZERO


# Claims motion whenever this ability is actively kiting (set each tick by
# `tick`), so the Enemy node's base chase/attack block steps aside and
# `drive_motion` below drives velocity/move_and_slide itself — the archetype
# refuses melee outright rather than merely preferring range.
func is_overriding_motion() -> bool:
	return _kiting


func drive_motion(_delta: float, enemy) -> void:
	if enemy == null:
		return
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D):
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	var move_speed: float = EnemyAIState.CHASE_SPEED
	var ms = enemy.get("move_speed")
	if ms != null:
		move_speed = float(ms)
	var dir := desired_direction(enemy.global_position, (player as Node2D).global_position)
	# Route through velocity + move_and_slide, same as the base chase/attack
	# path, so kiting respects the dungeon's wall collision instead of
	# phasing through it via a raw global_position write (issue #582
	# follow-up: the player's counter to this archetype is "corner it",
	# which requires walls to actually stop it).
	enemy.velocity = dir * move_speed
	enemy.move_and_slide()


func tick(delta: float, enemy) -> void:
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		_kiting = false
		return
	if is_active():
		# A zone already telegraphed keeps advancing (and the throw still
		# commits) even if aggro drops mid wind-up, same as every other
		# archetype's committed zone.
		_kiting = EnemyBehavior.is_aggroed(enemy)
		_advance_zone(delta, enemy)
		return
	# Aggro gate (issue #261 / PRD #518): an IDLE enemy must neither kite nor
	# accrue fire cadence — matches the aggro gate every other archetype and
	# the pre-archetype mobs share.
	if not EnemyBehavior.is_aggroed(enemy):
		_kiting = false
		return
	_kiting = true
	if _telegraph:
		_cooldown_elapsed += delta
		return
	_tick_inline_fire(delta, enemy)


# Pre-#582 firing path: no danger zone, no wind-up — the projectile itself is
# the tell. Kept byte-for-byte equivalent to the original so Pearl's in-play
# behavior (telegraph flag left false) is provably unchanged.
func _tick_inline_fire(delta: float, enemy) -> void:
	_fire_elapsed += delta
	if enemy == null:
		return
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D):
		return
	if _fire_elapsed < _fire_interval:
		return
	var player_node := player as Node2D
	var dist: float = enemy.global_position.distance_to(player_node.global_position)
	# Don't fire while inside the flee threshold — the enemy is busy
	# retreating — and gate by projectile range so a fire never leaves it
	# with a guaranteed miss.
	if dist <= _flee_range or dist > _projectile_max_range:
		return
	pending_fire_target = player_node.global_position
	_fire_elapsed = 0.0


# Telegraph path: locks a lane from the enemy to the player at wind-up start,
# same shape TelegraphedChargeAbility draws, so the throw reads with the same
# amber-to-red vocabulary as every other archetype's tell. Gated by the same
# flee/max-range rules as the inline path so a telegraphed throw is never a
# guaranteed miss or a point-blank throw either.
func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	var heading: Vector2 = (target as Vector2) - origin
	if heading == Vector2.ZERO:
		return null
	var dist := heading.length()
	if dist <= _flee_range or dist > _projectile_max_range:
		return null
	return DangerZoneShape.make_lane(
		origin, heading, dist, TELEGRAPH_LANE_WIDTH,
		TELEGRAPH_WINDUP_DURATION, TELEGRAPH_COMMIT_DURATION, TELEGRAPH_FADE_DURATION)


# Fires exactly where the telegraph pointed — the zone's own locked endpoint —
# so what was drawn and what gets thrown can never drift apart.
func _on_commit(_enemy, zone) -> void:
	pending_fire_target = zone.endpoint()
