class_name TutorialTrigger
extends RefCounted

# Pure should_trigger decision for the tutorial/help overlay (#600, PRD
# #596). Every scene's _ready calls this to decide whether to auto-show a
# topic right now. No node lookups, no overlay instantiation, no
# persistence writes -- mark_seen is the caller's job once the overlay
# closes, not this module's.

static func should_trigger(topic_id: String, seen_ids: Array, is_touch: bool) -> bool:
	var steps: Array[Dictionary] = TutorialCatalog.steps_for(topic_id)
	if steps.is_empty():
		return false
	if TutorialProgress.is_seen(seen_ids, topic_id):
		return false
	if not is_touch:
		var all_touch_only := true
		for step in steps:
			if not step.get("touch_only", false):
				all_touch_only = false
				break
		if all_touch_only:
			return false
	return true
