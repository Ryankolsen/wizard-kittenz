class_name TelegraphedChargeAbility
extends EnemyAbility

# Telegraphed charge archetype (PRD #518 / tracer slice #533). Draws a lane
# locked at telegraph start, then dashes down it. The player's counter is to
# sidestep the lane during the wind-up — the lane never re-aims, so stepping
# perpendicular is always enough.
#
# The dash owns the enemy's motion while the zone is committed, which is why
# is_overriding_motion is true for exactly that window: the Enemy node skips its
# chase/attack block and this ability writes global_position.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _length: float
var _width: float

var _dash_from: Vector2 = Vector2.ZERO
var _dash_to: Vector2 = Vector2.ZERO


func _init(
	cooldown_seconds: float = 6.0,
	windup_seconds: float = 0.8,
	commit_seconds: float = 0.35,
	fade_seconds: float = 0.3,
	lane_length: float = 140.0,
	lane_width: float = 24.0
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_length = lane_length
	_width = lane_width


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade


func lane_width() -> float:
	return _width


func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	var heading: Vector2 = (target as Vector2) - origin
	if heading == Vector2.ZERO:
		return null
	var zone := DangerZoneShape.make_lane(
		origin, heading, _length, _width, _windup, _commit, _fade)
	_dash_from = origin
	_dash_to = zone.endpoint()
	return zone


# Motion is this ability's only while the lane is live and committed — the dash
# itself. During the wind-up the enemy still moves under the normal state
# machine, which is what makes the telegraph read as a wind-up rather than a
# freeze.
func is_overriding_motion() -> bool:
	if active_zone == null:
		return false
	return active_zone.phase_at(zone_elapsed()) == DangerZoneShape.Phase.COMMIT


func _on_commit(enemy, zone) -> void:
	pending_hit_target = resolve_hit(enemy, zone)


# Advances the dash along the locked lane. Called by the ability pump each frame
# the charge owns motion, so the enemy sweeps the corridor it drew instead of
# teleporting to its end.
func drive_motion(delta: float, enemy) -> void:
	if enemy == null or active_zone == null or _commit <= 0.0:
		return
	var travelled: float = (zone_elapsed() - _windup) / _commit
	travelled = clampf(travelled, 0.0, 1.0)
	enemy.global_position = _dash_from.lerp(_dash_to, travelled)
	# delta is unused: the dash is driven off the zone's own clock so the
	# position always matches the phase the renderer is drawing.
	if delta < 0.0:
		pass
