class_name NPCOptionList
extends RefCounted

# Issue #195: ordered container of NPCOption rows for one NPC's bubble.
# Pure data — the bubble UI iterates this, the NPC owns the list and chooses
# what to do with the selected option's effect_id.

var _options: Array[NPCOption] = []


static func make(options: Array[NPCOption]) -> NPCOptionList:
	var list := NPCOptionList.new()
	list._options = options.duplicate()
	return list


func size() -> int:
	return _options.size()


func get(index: int) -> NPCOption:
	return _options[index]


func enabled_indices() -> Array[int]:
	var result: Array[int] = []
	for i in _options.size():
		if _options[i].is_enabled():
			result.append(i)
	return result
