class_name ZoneDenialAbility
extends EnemyAbility

# Zone-denial archetype (PRD #518 / issue #571). Telegraphs an amber disc,
# flashes red at commit, and drops a persistent FloorHazard on the exact spot
# once the zone fires — the disc is the tell, the hazard is what lingers
# after it. The player's counter is spacing: managing the floor and not
# getting cornered by an accumulating field of hazards.
#
# Reused later by Last Call Larry, Warden Wretched, the Angry Pigeon and the
# Rogue Roomba (PRD #518), so — same as PullAbility — every number arrives
# through _init and lives in AbilityLoadout rather than being hardcoded here.
#
# Determinism (PRD #518 "Co-op consistency" / issue #534's seeding scheme):
# a hazard's floor position must be identical on every client, so it cannot
# be derived from `target_position` (each client resolves that against its
# own local player only). Instead the placement is a seeded offset from the
# enemy's own position, rolled from a RandomNumberGenerator seeded off the
# enemy's stable spawn id via EnemyBehavior.spawn_id_of — the same scheme
# SummonAddsAbility.roll_summon_batch uses for its spawn offsets.
#
# The cap on hazards alive at once is tracked here rather than by having
# FloorHazard report back when it expires (that would need a new node-side
# callback wired through Enemy). Each firing that reaches commit pushes the
# configured hazard duration onto an internal countdown list; `tick` decays
# every entry by delta and drops it once it reaches zero, in lockstep with
# the real FloorHazard node's own `duration` timer (Enemy configures the
# spawned node with the same value this ability reports through
# `hazard_duration()`), so the two clocks can't drift apart.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _zone_radius: float
var _placement_radius: float
var _hazard_duration: float
var _hazard_slow_percent: float
var _hazard_damage_per_sec: float
var _hazard_radius: float
var _hazard_color: Color
var _cap: int

var _rng: RandomNumberGenerator = null
const _ZONE_RNG_SALT: String = "zone_denial:"

# Countdown (seconds remaining) for each hazard this ability believes is
# still alive on the floor. Decayed in `tick`.
var _hazard_remaining: Array = []

# Handoff to the Enemy node: the world position a FloorHazard should be
# spawned at, published once per firing on the ability's own commit edge.
# Cleared by the node once consumed — same publish/consume shape as
# `pending_zone`. Untyped so it can hold Vector2 or null.
var pending_hazard_spawn = null


func _init(
	cooldown_seconds: float = 6.0,
	windup_seconds: float = 0.7,
	commit_seconds: float = 0.2,
	fade_seconds: float = 0.3,
	zone_radius: float = 36.0,
	hazard_duration: float = 4.0,
	hazard_slow_percent: float = 0.35,
	hazard_damage_per_sec: float = 4.0,
	hazard_radius: float = 32.0,
	hazard_color: Color = Color(0.55, 0.35, 0.15, 0.45),
	cap: int = 3,
	placement_radius: float = 90.0
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_zone_radius = zone_radius
	_hazard_duration = hazard_duration
	_hazard_slow_percent = hazard_slow_percent
	_hazard_damage_per_sec = hazard_damage_per_sec
	_hazard_radius = hazard_radius
	_hazard_color = hazard_color
	_cap = cap
	_placement_radius = placement_radius


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade

func hazard_duration() -> float:
	return _hazard_duration

func hazard_slow_percent() -> float:
	return _hazard_slow_percent

func hazard_damage_per_sec() -> float:
	return _hazard_damage_per_sec

func hazard_radius() -> float:
	return _hazard_radius

func hazard_color() -> Color:
	return _hazard_color

func alive_hazard_count() -> int:
	return _hazard_remaining.size()


func _ensure_rng(enemy) -> RandomNumberGenerator:
	if _rng != null:
		return _rng
	_rng = RandomNumberGenerator.new()
	var eid := EnemyBehavior.spawn_id_of(enemy)
	if eid == "":
		_rng.randomize()
	else:
		_rng.seed = hash(_ZONE_RNG_SALT + eid)
	return _rng


# Pure roll of one hazard's floor position, seeded from the enemy id. Exposed
# directly (mirroring SummonAddsAbility.roll_summon_batch) so determinism is
# testable without waiting out the cooldown.
func roll_zone_origin(enemy) -> Vector2:
	var rng := _ensure_rng(enemy)
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(0.0, _placement_radius)
	var base: Vector2 = enemy.get("global_position") if enemy != null else Vector2.ZERO
	return (base as Vector2) + Vector2(cos(angle), sin(angle)) * dist


# Declines the firing (and, per the base class's begin() contract, leaves the
# cooldown running rather than resetting it) once the cap is already full —
# the same "a decline is a routine event" shape RetreatAndFireAbility's range
# gate introduced.
func _build_zone(enemy) -> DangerZoneShape:
	if enemy == null:
		return null
	if _hazard_remaining.size() >= _cap:
		return null
	var origin := roll_zone_origin(enemy)
	return DangerZoneShape.make_disc(origin, _zone_radius, _windup, _commit, _fade)


# Fire-once edge already guaranteed by the base class (EnemyAbility._advance_zone
# calls this exactly once per firing, on the frame the zone leaves wind-up) —
# so one call here is one hazard-spawn request, never one per commit frame.
func _on_commit(_enemy, zone) -> void:
	_hazard_remaining.append(_hazard_duration)
	pending_hazard_spawn = zone.origin


func tick(delta: float, enemy) -> void:
	super.tick(delta, enemy)
	for i in range(_hazard_remaining.size() - 1, -1, -1):
		_hazard_remaining[i] -= delta
		if _hazard_remaining[i] <= 0.0:
			_hazard_remaining.remove_at(i)
