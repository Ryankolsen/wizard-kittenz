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

func apply(type_id: String, target) -> PowerUpEffect:
	if _active.has(type_id):
		var existing: PowerUpEffect = _active[type_id]
		existing.refresh()
		return existing
	var effect: PowerUpEffect = PowerUpEffect.make(type_id)
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
