class_name TutorialProgress
extends RefCounted

# Pure seen/mark_seen tracking for the tutorial/help overlay (#598, PRD #596).
# Operates on a plain Array of topic-id strings passed in by the caller — no
# persistence, no scene tree, no dependency on AccountSaveData/GameState, and
# no knowledge of TutorialCatalog's known topic ids. Persistence wiring is a
# separate slice (#599). Mirrors DailyStreakEngine.resolve()'s style of
# returning new state rather than mutating in place.

static func is_seen(seen_ids: Array, topic_id: String) -> bool:
	if topic_id == "":
		return false
	return seen_ids.has(topic_id)


static func mark_seen(seen_ids: Array, topic_id: String) -> Array:
	var result := seen_ids.duplicate()
	if topic_id == "":
		return result
	if not result.has(topic_id):
		result.append(topic_id)
	return result
