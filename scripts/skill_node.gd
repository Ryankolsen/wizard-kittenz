class_name SkillNode
extends RefCounted

# One node in a SkillTree. Holds the spell granted on unlock, the skill-point
# cost to unlock, and the IDs of nodes that must be unlocked first. Modeled as
# RefCounted (not Resource) because the persisted state is just the unlocked
# id set in KittenSaveData — the static node definitions live in code via
# SkillTree.make_*_tree() factories.

var id: String = ""
var display_name: String = ""
var cost: int = 1
var prerequisite_ids: Array = []
var unlocked: bool = false
var spell: Spell = null

static func make(n_id: String, name: String, spell_ref: Spell, prereqs: Array = [], cost_val: int = 1) -> SkillNode:
	var n := SkillNode.new()
	n.id = n_id
	n.display_name = name
	n.spell = spell_ref
	n.prerequisite_ids = prereqs.duplicate()
	n.cost = cost_val
	return n
