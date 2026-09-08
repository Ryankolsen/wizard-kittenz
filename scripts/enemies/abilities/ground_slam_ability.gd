class_name GroundSlamAbility
extends EnemyAbility

# Ground-slam archetype (PRD #518 / issue #573). An expanding shockwave ring
# centred on the enemy itself — unlike the lane/tether/disc archetypes, this
# one needs no target position at all, since the enemy is always its own
# telegraph origin. The player's counter is getting outside the ring before
# the expanding edge reaches them: the dangerous region is the sweeping edge,
# not a static area, so standing at the boss's feet after the wave has passed
# is safe again.
#
# Reused by DJ Dubstep's beat-locked slam (out of scope here), so the tuning
# arrives through _init and lives in AbilityLoadout, same as every other
# archetype.
#
# The base class's fire-once commit edge (EnemyAbility._advance_zone) only
# calls _on_commit once, at the single frame the zone first leaves wind-up —
# which for a ring is the instant the edge radius is still 0. A player is
# essentially never standing exactly on that first frame's edge, so hit
# resolution here can't be a single _on_commit check the way the lane/disc
# archetypes do it; the wave has to be checked across the whole commit
# window as its edge sweeps outward. `_on_commit` is therefore left a no-op
# and `tick` does the continuous check instead, guarded by `_hit_landed` so
# a player caught while the (width-wide) band sweeps across their position
# over several frames is still only ever hit once per firing.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _max_radius: float
var _band_width: float

var _hit_landed: bool = false


func _init(
	cooldown_seconds: float = 6.0,
	windup_seconds: float = 0.7,
	commit_seconds: float = 2.0,
	fade_seconds: float = 0.3,
	max_radius: float = 140.0,
	band_width: float = 28.0
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_max_radius = max_radius
	_band_width = band_width


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade

func max_radius() -> float:
	return _max_radius

func band_width() -> float:
	return _band_width


# Ground slam needs no target — it always fires centred on the enemy's own
# position, so a null player reference never blocks the telegraph itself
# (only hit resolution, below, needs a player to check against).
func _build_zone(enemy) -> DangerZoneShape:
	if enemy == null:
		return null
	var origin: Vector2 = enemy.global_position
	return DangerZoneShape.make_ring(
		origin, _max_radius, _band_width, _windup, _commit, _fade)


func begin(enemy) -> void:
	_hit_landed = false
	super.begin(enemy)


# See the class comment: the payload lands here, on whichever frame during
# the commit window the expanding edge actually reaches the player, rather
# than on the single fire-once frame the base class calls _on_commit.
func tick(delta: float, enemy) -> void:
	super.tick(delta, enemy)
	if active_zone == null or _hit_landed:
		return
	if active_zone.phase_at(zone_elapsed()) != DangerZoneShape.Phase.COMMIT:
		return
	var caught = resolve_hit(enemy, active_zone)
	if caught == null:
		return
	_hit_landed = true
	pending_hit_target = caught
