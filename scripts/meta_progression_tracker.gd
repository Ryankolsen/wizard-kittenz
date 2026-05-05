class_name MetaProgressionTracker
extends RefCounted

# Lifetime stats used to evaluate UnlockRegistry conditions. Keeps a tally of
# the stuff that gates class / class-tier unlocks: total dungeons cleared, and
# the max level reached on each class. Stored separately from CharacterData
# because these are *meta* stats — they survive past a single kitten dying or
# being replaced, and they're class-name-keyed strings (so a future class added
# via data only needs a new entry in the dictionary, not a new field).

var dungeons_completed: int = 0
# class-name string (lowercase, matches CharacterFactory.class_from_name) ->
# highest level ever reached on that class. Tracked per-class so the
# registry can gate upgrades like "reach level 5 with Mage".
var max_level_per_class: Dictionary = {}

func record_dungeon_complete() -> void:
	dungeons_completed += 1

# Records the level reached on a class, keeping only the maximum seen so far.
# class_name_str is lowercase — same convention as CharacterFactory.
func record_level_reached(class_name_str: String, level: int) -> void:
	var key := class_name_str.to_lower()
	var prev: int = int(max_level_per_class.get(key, 0))
	if level > prev:
		max_level_per_class[key] = level

func max_level_for(class_name_str: String) -> int:
	return int(max_level_per_class.get(class_name_str.to_lower(), 0))

# Stat lookup by string path. Supports the simple top-level stats and a dotted
# form for per-class lookups: "max_level_per_class.mage" -> the level int. The
# UnlockRegistry conditions reference stats by this path so a new condition
# dict can be added without UnlockRegistry knowing how to look it up.
func get_stat(stat_path: String) -> int:
	if stat_path == "dungeons_completed":
		return dungeons_completed
	if stat_path.begins_with("max_level_per_class."):
		var key := stat_path.substr("max_level_per_class.".length())
		return max_level_for(key)
	return 0

func to_dict() -> Dictionary:
	return {
		"dungeons_completed": dungeons_completed,
		"max_level_per_class": max_level_per_class.duplicate(),
	}

static func from_dict(d: Dictionary) -> MetaProgressionTracker:
	var t := MetaProgressionTracker.new()
	t.dungeons_completed = int(d.get("dungeons_completed", 0))
	var per_class = d.get("max_level_per_class", {})
	if per_class is Dictionary:
		for k in per_class.keys():
			t.max_level_per_class[String(k).to_lower()] = int(per_class[k])
	return t
