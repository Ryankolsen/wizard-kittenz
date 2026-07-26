class_name SkillNode
extends RefCounted

# One node in a SkillTree. Holds the spell granted on unlock, the skill-point
# cost to unlock, and the IDs of nodes that must be unlocked first. Modeled as
# RefCounted (not Resource) because the persisted state is just the unlocked
# id set in KittenSaveData — the static node definitions live in code via
# SkillTree.make_*_tree() factories.

var id: String = ""
var display_name: String = ""
var description: String = ""
var cost: int = 1
var prerequisite_ids: Array = []
var unlocked: bool = false
var spell: Spell = null
var level_required: int = 1
# Cat-tier gating (PRD #418 / issue #420). -1 (default) means "no class
# restriction" — unlockable by level alone, same as every pre-Cat-tier node.
# When set to a CharacterData.CharacterClass value, SkillUnlockChecker also
# requires the character's actual character_class to match before unlocking,
# so a Kitten that never evolved can't unlock Cat-tier nodes by leveling.
var required_class: int = -1

static func make(n_id: String, name: String, spell_ref: Spell, prereqs: Array = [], cost_val: int = 1, level_req: int = 1, desc: String = "", required_class_val: int = -1) -> SkillNode:
	var n := SkillNode.new()
	n.id = n_id
	n.display_name = name
	n.description = desc
	n.spell = spell_ref
	n.prerequisite_ids = prereqs.duplicate()
	n.cost = cost_val
	n.level_required = level_req
	n.required_class = required_class_val
	return n
