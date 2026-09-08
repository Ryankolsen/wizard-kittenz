class_name KnockbackShoveAbility
extends EnemyAbility

# Knockback-shove archetype (PRD #518 / issue #574). Completes Big Bruiser
# Buster: standing in his melee range gets shoved away, so the fight teaches
# players to respect his space. The player's counter is fighting at range —
# this only telegraphs when the player is actually caught in melee at the
# moment of firing, so a shove at nobody never burns the cooldown.
#
# This is PullAbility's problem with the sign reversed: same
# resolve-then-displace shape (write the caught player's global_position,
# publish the target for node-side VFX), but outward instead of inward.
# Issue #574's "Unsure" note asks whether to reuse `pending_pull_target` or
# publish a second field — this reuses it, since the node-side consumer is
# identical either way and a twin field would be identical plumbing for no
# benefit.
#
# Unlike Pull's tether (aimed at a locked target point, reach clamped to
# max_reach), the zone here is a disc centred on the enemy at melee range:
# there is no directional aim to a poke, only "is the player standing next to
# me". The shove itself is a fixed distance rather than gap-clamped like
# Pull's drag — pushing outward has no "past the enemy" geometry to clamp
# against, so the configured knockback distance already is the maximum.
#
# Reused by The Bouncer (out of scope here), so tuning arrives through _init
# and lives in AbilityLoadout, per the PRD's "adding a move is a data change"
# goal.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _melee_range: float
var _knockback_distance: float


func _init(
	cooldown_seconds: float = 4.0,
	windup_seconds: float = 0.35,
	commit_seconds: float = 0.15,
	fade_seconds: float = 0.2,
	melee_range: float = 70.0,
	knockback_distance: float = 90.0
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_melee_range = melee_range
	_knockback_distance = knockback_distance


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade

func melee_range() -> float:
	return _melee_range

func knockback_distance() -> float:
	return _knockback_distance


# Only telegraphs when the player is actually within melee range at the
# moment of firing. Returning null is a decline, not a miss: per
# EnemyAbility.begin, a declined build leaves the cooldown running instead of
# resetting it, so an out-of-range player doesn't pin the cadence at zero
# forever — the next tick just retries.
func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	if origin.distance_to(target as Vector2) > _melee_range:
		return null
	return DangerZoneShape.make_disc(origin, _melee_range, _windup, _commit, _fade)


# Shoves the caught player outward along the enemy-to-player vector — the same
# resolve-then-displace shape as PullAbility._on_commit, sign reversed via
# `zone.pull_direction`. `resolve_hit` checks the player's *current* position
# against the zone (locked at telegraph start), so a player who stepped out of
# melee range during the wind-up resolves to null here and is never shoved.
func _on_commit(enemy, zone) -> void:
	var caught = resolve_hit(enemy, zone)
	if caught == null:
		return
	var dir: Vector2 = -zone.pull_direction(caught.global_position)
	if dir == Vector2.ZERO:
		return
	caught.global_position += dir * _knockback_distance
	pending_pull_target = caught
