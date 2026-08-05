class_name ScrollCatalog
extends RefCounted

# Static registry of every scroll in the game (issue #456 stub). Empty until
# real scroll content is designed (deferred per #453's Out of Scope) — this
# just establishes the home for that follow-up, mirroring PotionCatalog.

static func all() -> Array:
	var out: Array = []
	return out

static func find(scroll_id: String) -> ScrollDefinition:
	for d in all():
		if d.id == scroll_id:
			return d
	return null
