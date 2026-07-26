class_name StatDelta
extends RefCounted

const _STAT_KEYS := ["max_hp", "attack", "defense", "speed"]
const _STAT_LABELS := ["Max HP", "Attack", "Defense", "Speed"]

static func compute(old_stats: Dictionary, new_stats: Dictionary) -> Array:
	var entries := []
	for i in range(_STAT_KEYS.size()):
		var key: String = _STAT_KEYS[i]
		var old_value: float = old_stats.get(key, 0)
		var new_value: float = new_stats.get(key, 0)
		entries.append({
			"label": _STAT_LABELS[i],
			"old_value": old_value,
			"new_value": new_value,
			"delta": new_value - old_value,
		})
	return entries
