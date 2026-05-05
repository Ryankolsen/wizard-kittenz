class_name QuickStartController
extends RefCounted

# Quick Start path: tap a class -> CharacterData with a randomly-picked
# silly name. Stateless static API so the picker UI calls it directly
# without instantiating. NameSuggester is constructed per-call so the
# random draw is fresh; persistent suggester state would mean two
# consecutive Quick Start sessions could repeat. The 2-tap acceptance
# criterion (Quick Start button -> class button -> in game) is enforced
# by the scene wiring, not this layer; this is just the data factory.

static func create_for_class(class_name_str: String) -> CharacterData:
	var suggester := NameSuggester.new()
	var n := suggester.get_random_name()
	return CharacterFactory.create_default(class_name_str, n)

# Apply a name + appearance edit to an existing CharacterData without
# touching xp / level / skill_points. Used by the Edit Kitten flow
# from the pause menu (issue #5 acceptance: "updating identity without
# resetting progression"). Mutates in place; returns nothing — same
# shape as PartyScaler.remove_scaling.
static func apply_identity_edit(c: CharacterData, new_name: String, new_appearance: int) -> void:
	if c == null:
		return
	if new_name.strip_edges() != "":
		c.character_name = new_name
	c.appearance_index = new_appearance
