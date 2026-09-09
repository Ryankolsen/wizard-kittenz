class_name ConeSprayAbility
extends EnemyAbility

# Cone-spray archetype (PRD #518 / issue #576). Karaoke Karen screeches in a
# sustained cone along her own facing while her called-in adds close in, so
# the player solves two spacing problems at once. The cone's facing is
# captured once, at telegraph start (`_build_zone` reads `target_position`
# exactly once, inside `begin`) — it never re-aims at the player during the
# wind-up, which is what makes flanking behind the enemy a real counter
# rather than something the cone could just turn to follow.
#
# Sustained-damage decision (the PRD's "sustained cone" language, pinned by
# test_cone_spray_ability.gd): this archetype TICKS damage across the whole
# commit window rather than landing a single hit at commit start. A player
# standing in the cone for the entire commit window is caught once per
# `_tick_interval` seconds, not once total — sustained means "keep taking
# it while you stand there," the same way a lingering hazard or a channel
# would read, and distinct from the lane/disc archetypes' one-shot commit
# and from the ring's "hit exactly once as the wave passes" latch. Ticking
# stops the instant the zone leaves COMMIT for FADE.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _length: float
var _half_angle_degrees: float
var _tick_interval: float

var _tick_elapsed: float = 0.0


func _init(
	cooldown_seconds: float = 5.0,
	windup_seconds: float = 0.9,
	commit_seconds: float = 1.2,
	fade_seconds: float = 0.3,
	cone_length: float = 180.0,
	half_angle_degrees: float = 35.0,
	tick_interval: float = 0.25
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_length = cone_length
	_half_angle_degrees = half_angle_degrees
	_tick_interval = tick_interval


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade


# Locks the cone's facing at telegraph start: `target_position` is read here,
# exactly once (inside `begin`, never again for this firing), so a player who
# moves during the wind-up cannot drag the cone's aim with them.
func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	var facing: Vector2 = (target as Vector2) - origin
	return DangerZoneShape.make_cone(
		origin, facing, _length, _half_angle_degrees, _windup, _commit, _fade)


func begin(enemy) -> void:
	_tick_elapsed = 0.0
	super.begin(enemy)


# See the class comment: the base class's fire-once `_on_commit` edge only
# fires on the single frame the zone first leaves wind-up, which would land
# one hit and never re-check for the rest of the commit window. A sustained
# cone needs damage re-checked throughout that window instead, so `_on_commit`
# is left a no-op and this override does the periodic check, the same shape
# GroundSlamAbility uses for its own continuous check (there latched to fire
# once; here intentionally allowed to fire again every `_tick_interval`).
func tick(delta: float, enemy) -> void:
	super.tick(delta, enemy)
	if active_zone == null:
		_tick_elapsed = 0.0
		return
	if active_zone.phase_at(zone_elapsed()) != DangerZoneShape.Phase.COMMIT:
		return
	_tick_elapsed += delta
	if _tick_elapsed < _tick_interval:
		return
	_tick_elapsed = 0.0
	var caught = resolve_hit(enemy, active_zone)
	if caught == null:
		return
	pending_hit_target = caught
