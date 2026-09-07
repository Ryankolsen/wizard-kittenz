class_name PullAbility
extends EnemyAbility

# Pull archetype (PRD #518 / tracer slice #533). Telegraphs a tether between the
# enemy and the player's position at telegraph start, then drags whoever is on
# that line toward the enemy. The player's counter is spacing: break the line
# during the wind-up and the tether commits on empty floor.
#
# Tuning arrives through _init so the archetype is shared and the numbers live
# in AbilityLoadout, per the PRD's "adding a move is a data change" goal.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _max_reach: float
var _width: float
var _pull_distance: float


func _init(
	cooldown_seconds: float = 5.0,
	windup_seconds: float = 0.9,
	commit_seconds: float = 0.25,
	fade_seconds: float = 0.3,
	max_reach: float = 160.0,
	tether_width: float = 28.0,
	pull_distance: float = 48.0
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_max_reach = max_reach
	_width = tether_width
	_pull_distance = pull_distance


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade


func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	var span: Vector2 = (target as Vector2) - origin
	if span.length() > _max_reach:
		span = span.normalized() * _max_reach
	return DangerZoneShape.make_tether(
		origin, origin + span, _width, _windup, _commit, _fade)


# Drags the caught player along the zone's own reported pull direction, so the
# displacement and the drawn tether cannot disagree.
func _on_commit(enemy, zone) -> void:
	var caught = resolve_hit(enemy, zone)
	if caught == null:
		return
	var dir: Vector2 = zone.pull_direction(caught.global_position)
	if dir == Vector2.ZERO:
		return
	# Never drag the player past the enemy itself — clamp to the gap.
	var gap: float = caught.global_position.distance_to(enemy.global_position)
	caught.global_position += dir * minf(_pull_distance, maxf(0.0, gap - 8.0))
	pending_pull_target = caught
