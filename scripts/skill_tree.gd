class_name SkillTree
extends RefCounted

# Directed acyclic graph of SkillNodes. The graph shape lives in the per-class
# factory (`make_mage_tree`, etc.); the runtime-mutable state is each node's
# `unlocked` flag, which is what the save layer round-trips.

var nodes: Array = []

func add_node(node: SkillNode) -> void:
	nodes.append(node)

func find(node_id: String) -> SkillNode:
	for n in nodes:
		if n.id == node_id:
			return n
	return null

func unlocked_ids() -> Array:
	var out: Array = []
	for n in nodes:
		if n.unlocked:
			out.append(n.id)
	return out

# Re-applies a saved unlocked-id set onto the freshly-built tree. Unknown ids
# are ignored so an old save against a renamed node won't crash — it just
# silently drops the stale entry.
func apply_unlocked_ids(ids: Array) -> void:
	for n in nodes:
		n.unlocked = ids.has(n.id)

func get_unlocked_spells() -> Array:
	var out: Array = []
	for n in nodes:
		if n.unlocked and n.spell != null:
			out.append(n.spell)
	return out

# Mage tree per #9: Fireball (base) -> Frost Nova (req Fireball) ->
# Arcane Surge (req Frost Nova). EffectKind values diverge so each spell is a
# distinct combat behavior (single-target damage / area / self-buff).
# Cooldowns scale with power: 0.8s / 1.5s / 4.0s. Costs are 1 skill point each
# while skill_points come from level-ups; tune once #8 + playtest data lands.
static func make_mage_tree() -> SkillTree:
	var t := SkillTree.new()
	var fireball := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	var frost_nova := Spell.make("frost_nova", "Frost Nova", Spell.EffectKind.AREA, 4, 1.5)
	var arcane_surge := Spell.make("arcane_surge", "Arcane Surge", Spell.EffectKind.BUFF, 5, 4.0)
	t.add_node(SkillNode.make("fireball", "Fireball", fireball, [], 1))
	t.add_node(SkillNode.make("frost_nova", "Frost Nova", frost_nova, ["fireball"], 1))
	t.add_node(SkillNode.make("arcane_surge", "Arcane Surge", arcane_surge, ["frost_nova"], 1))
	return t
