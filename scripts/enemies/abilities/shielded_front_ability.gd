class_name ShieldedFrontAbility
extends EnemyAbility

# Shielded-front archetype (PRD #518 / issue #578). Completes The Bouncer: he
# cannot be hurt from the front, so the whole fight is about getting behind
# him. Built as a physical shield hazard on the existing danger-zone
# geometry/renderer (#533) rather than an invisible take-damage-arc check —
# this is issue #577's recorded decision, restated in full below (per that
# issue's requirement) so this file is self-contained for the next reader.
#
# #577's recorded co-op rule (option 3, deterministic facing), implemented
# here exactly as decided:
#   - What facing derives from: the boss's own movement direction (its
#     velocity), or a seeded rotation if idle — never from `target_position`
#     / `_player_ref`, which resolves per-client. Target-based facing would
#     let two clients disagree on whether the same hit landed inside the
#     shield, which (since damage is routed identically on every client from
#     locally-simulated state) would desync the boss's HP between clients —
#     one client seeing him at 40%, another at 55%, for the same fight.
#   - When sampled: on this ability's own tick cadence, resampled at a fixed
#     interval rather than every physics frame, so the shield doesn't spin to
#     track the boss's frame-to-frame micro-movement.
#   - Damage floor: a hit landing inside the shield is reduced, never
#     blocked outright — `_min_damage_leak` always gets through, so a player
#     who can't flank yet is slowed, not hard-stopped. Hits from outside the
#     shield's arc are unreduced.
#   - Network traffic: none. Facing is derived locally, identically, on every
#     client from data already simulated locally (movement) or already
#     synchronized (the seeded spawn id) — no new packet.
#   - Solo vs. co-op: identical behavior in both; this replaces target-based
#     facing everywhere; it is not a co-op-only fallback.
#
# Unlike every other archetype in this file, this one protects the enemy
# rather than threatening the player, so it never enters the fire-once
# wind-up/commit/fade cycle every other archetype's `_build_zone` drives:
# `wants_to_fire` stays pinned to false, the same "tick-only participant in
# the generic pump" shape EnrageAbility introduced for a payload with nothing
# to telegraph. What IS telegraphed — continuously, not as a wind-up — is the
# shield's own position: a DangerZoneShape.DISC published directly through
# the inherited `pending_zone` handoff on every facing resample, satisfying
# the "must be visible, discoverable in play" AC through the same renderer
# every other archetype uses, without ever setting `active_zone` (so it can
# never win the pump's "one telegraph at a time" arbitration and starve a
# sibling ability — e.g. Bouncer's own knockback shove — of ever firing).
#
# The disc's containment (`DangerZoneShape.contains`) is not itself consulted
# for the reduction: it has no notion of an angle, only a radius. The
# reduction is a dedicated bearing check against the last-sampled facing
# (see `reduce_damage` / `_within_arc`) — the disc is the visual read of
# "the shield is up and roughly here", the bearing check is the actual rule.
#
# Enemy.gd integration (issue #578's "take-damage path" seam): `reduce_damage`
# is the single function every one of Enemy.apply_shield_reduction's callers
# funnels through — Player._apply_melee_damage ("contact"),
# Player._apply_spell_basic_damage (the wizard's basic/auto CAST attack), and
# Player._apply_spell_effect (a cast quickbar spell) — mirroring the one-
# shared-choke-point shape issue #566 established for the enemy's own
# outgoing damage, applied here to damage the enemy receives instead.

var _half_angle_degrees: float
var _reduction_fraction: float
var _min_damage_leak: int
var _resample_interval: float
var _shield_offset: float
var _shield_radius: float
var _shield_color: Color

var _facing: Vector2 = Vector2.RIGHT
var _resample_elapsed: float = 0.0
var _has_sampled: bool = false

var _rng: RandomNumberGenerator = null
var _idle_facing_cache = null  # Vector2 once rolled, else null
const _SHIELD_RNG_SALT: String = "shielded_front:"


func _init(
	half_angle_degrees: float = 75.0,
	reduction_fraction: float = 0.7,
	min_damage_leak: int = 1,
	resample_interval_seconds: float = 0.5,
	shield_offset: float = 40.0,
	shield_radius: float = 34.0,
	shield_color: Color = Color(0.3, 0.6, 1.0, 0.4)
) -> void:
	_half_angle_degrees = clampf(half_angle_degrees, 0.0, 180.0)
	_reduction_fraction = clampf(reduction_fraction, 0.0, 1.0)
	_min_damage_leak = maxi(1, min_damage_leak)
	_resample_interval = maxf(0.01, resample_interval_seconds)
	_shield_offset = shield_offset
	_shield_radius = shield_radius
	_shield_color = shield_color


func half_angle_degrees() -> float:
	return _half_angle_degrees

func reduction_fraction() -> float:
	return _reduction_fraction

func min_damage_leak() -> int:
	return _min_damage_leak

func resample_interval() -> float:
	return _resample_interval


# See the class comment: this archetype never fires through the zone pump.
func wants_to_fire() -> bool:
	return false

func _build_zone(_enemy) -> DangerZoneShape:
	return null


# Resamples facing (and republishes the shield's visual disc) once per
# `_resample_interval`, gated on aggro the same way the base class's own
# cooldown accrual is (EnemyAbility.tick) — an enemy that hasn't engaged
# anyone doesn't need a shield telegraph on screen either.
func tick(delta: float, enemy) -> void:
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_resample_elapsed += delta
	if not _has_sampled or _resample_elapsed >= _resample_interval:
		_resample_elapsed = 0.0
		_has_sampled = true
		resample_facing(enemy)


# Recomputes and caches the facing direction, and republishes the shield's
# visible zone at the new facing. Exposed directly (mirroring
# ZoneDenialAbility.roll_zone_origin) so tests can force a resample without
# waiting out the interval or the aggro gate.
func resample_facing(enemy) -> Vector2:
	_facing = _compute_facing(enemy)
	_publish_zone(enemy)
	return _facing

func facing() -> Vector2:
	return _facing


# #577's rule: movement direction first, a seeded idle rotation as the
# fallback — never `target_position`.
func _compute_facing(enemy) -> Vector2:
	if enemy == null:
		return Vector2.RIGHT
	var vel = enemy.get("velocity")
	if vel != null and (vel as Vector2) != Vector2.ZERO:
		return (vel as Vector2).normalized()
	return _idle_facing(enemy)


# Rolled once and cached for this ability's lifetime — a stable rotation
# while idle, not a fresh roll every idle tick, so it reads as "facing some
# direction" rather than spinning in place.
func _idle_facing(enemy) -> Vector2:
	if _idle_facing_cache != null:
		return _idle_facing_cache
	var rng := _ensure_rng(enemy)
	var angle := rng.randf_range(0.0, TAU)
	_idle_facing_cache = Vector2(cos(angle), sin(angle))
	return _idle_facing_cache


# Same seeded-per-enemy-id RNG scheme as ZoneDenialAbility._ensure_rng
# (issue #534's determinism), salted separately so this stream never
# collides with another archetype's.
func _ensure_rng(enemy) -> RandomNumberGenerator:
	if _rng != null:
		return _rng
	_rng = RandomNumberGenerator.new()
	var eid := EnemyBehavior.spawn_id_of(enemy)
	if eid == "":
		_rng.randomize()
	else:
		_rng.seed = hash(_SHIELD_RNG_SALT + eid)
	return _rng


# Publishes a fresh disc, offset in front of the enemy along the current
# facing, through the inherited `pending_zone` handoff — bypassing `begin()`
# entirely (see class comment for why). windup=0 so the renderer reads it as
# already committed (there is nothing to telegraph, the shield is already
# up); its lifetime spans one resample interval plus a hair of overlap so the
# outgoing disc doesn't visibly blink before the next one is published.
func _publish_zone(enemy) -> void:
	if enemy == null:
		return
	var pos = enemy.get("global_position")
	if pos == null:
		return
	var origin: Vector2 = (pos as Vector2) + _facing * _shield_offset
	pending_zone = DangerZoneShape.make_disc(
		origin, _shield_radius, 0.0, _resample_interval + 0.05, 0.05)


# Whether `attacker_position` sits inside the shield's frontal arc around
# `enemy`, measured against the last-sampled facing. Inclusive at the
# boundary, matching every DangerZoneShape edge's own inclusive convention
# (see e.g. DangerZoneShape._contains_geometry's DISC branch).
func _within_arc(enemy, attacker_position) -> bool:
	if enemy == null or attacker_position == null:
		return false
	var pos = enemy.get("global_position")
	if pos == null:
		return false
	var to_attacker: Vector2 = (attacker_position as Vector2) - (pos as Vector2)
	if to_attacker == Vector2.ZERO:
		# Coincident attacker: no bearing to measure. Treated as dead ahead
		# (inside the shield) rather than risking a NaN out of normalized().
		return true
	var facing_dir := _facing if _facing != Vector2.ZERO else Vector2.RIGHT
	var angle := absf(facing_dir.angle_to(to_attacker.normalized()))
	# A small epsilon absorbs float error from the trig round-trip so a hit
	# constructed to land exactly on the boundary (as the unit tests do)
	# resolves to the documented inclusive side rather than flickering with
	# floating-point noise.
	return angle <= deg_to_rad(_half_angle_degrees) + 0.0001


# The reduction hook. Given the raw damage a hit would otherwise deal to
# `enemy` and the position it arrived from, returns the damage actually
# dealt: unreduced from outside the shield's arc, reduced by
# `_reduction_fraction` from inside it, and never dropping below
# `_min_damage_leak` (never zero) once anything is dealt at all.
func reduce_damage(enemy, attacker_position, damage: int) -> int:
	if attacker_position == null:
		return damage
	if damage <= 0:
		return damage
	if not _within_arc(enemy, attacker_position):
		return damage
	var reduced := int(floor(float(damage) * (1.0 - _reduction_fraction)))
	reduced = maxi(reduced, _min_damage_leak)
	reduced = mini(reduced, damage)
	return reduced
