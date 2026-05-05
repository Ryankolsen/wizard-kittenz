extends Node

var current_character: CharacterData = null
var skill_tree: SkillTree = null

func _ready() -> void:
	_try_load_save()

func _try_load_save() -> void:
	var save_data := SaveManager.load()
	if save_data == null:
		return
	var c := CharacterData.new()
	save_data.apply_to(c)
	current_character = c
	skill_tree = _build_tree_for(c)
	skill_tree.apply_unlocked_ids(save_data.unlocked_skill_ids)

func set_character(c: CharacterData) -> void:
	current_character = c
	skill_tree = _build_tree_for(c)

func clear() -> void:
	current_character = null
	skill_tree = null

# Per-class tree builder. Each class gets its own factory so unlocks on one
# class's tree never bleed into another's (independent-trees acceptance
# criterion from #10). Unknown class falls through to the mage tree as a safe
# default — better than returning null and forcing every call site to
# null-check.
func _build_tree_for(c: CharacterData) -> SkillTree:
	match c.character_class:
		CharacterData.CharacterClass.MAGE: return SkillTree.make_mage_tree()
		CharacterData.CharacterClass.THIEF: return SkillTree.make_thief_tree()
		CharacterData.CharacterClass.NINJA: return SkillTree.make_ninja_tree()
	return SkillTree.make_mage_tree()
