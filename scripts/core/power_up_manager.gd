class_name PowerUpManager
extends RefCounted

# Tracks the active set of power-up effects on a target. Applying an
# already-active type refreshes its timer rather than stacking — matches
# the issue's "two pickups in sequence refresh, not stack" criterion. On
# expiry, the effect's remove() reverts whatever stat delta it applied.
#
# Stateful instance over (target,) so call sites read like
# `manager.apply("catnip", c)` per the issue spec. Same shape as
# SkillTreeManager, just over a different domain.

var _active: Dictionary = {}

# Single apply entry. `duration < 0` resolves to the registry default for the
# kind (pickup path); an explicit value is passed through (debuff path, where
# the enemy behavior tunes the timer). Refresh-not-stack: re-applying an
# already-active kind refreshes the in-flight effect's remaining timer and
# discards the would-be new instance, so two pickups / re-hits don't double
# the magnitude.
func apply(type_id: String, target, duration: float = -1.0) -> PowerUpEffect:
	if _active.has(type_id):
		var existing: PowerUpEffect = _active[type_id]
		existing.refresh()
		return existing
	var effect: PowerUpEffect = PowerUpEffect.make(type_id, duration)
	if effect == null:
		return null
	effect.apply_to(target)
	_active[type_id] = effect
	return effect

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	var expired: Array = []
	for type_id in _active.keys():
		var effect: PowerUpEffect = _active[type_id]
		effect.tick(dt)
		if effect.is_expired():
			expired.append(type_id)
	for type_id in expired:
		_active[type_id].remove()
		_active.erase(type_id)

func is_active(type_id: String) -> bool:
	return _active.has(type_id)

func get_active(type_id: String) -> PowerUpEffect:
	return _active.get(type_id, null)

func active_count() -> int:
	return _active.size()
