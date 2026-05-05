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

# Per-class tree builder. Mage gets the Fireball/Frost Nova/Arcane Surge tree
# from #9; Thief and Ninja still fall back to the mage tree until #10 lands
# class-specific spell sets — better than returning null and forcing every
# call site to null-check.
func _build_tree_for(c: CharacterData) -> SkillTree:
	match c.character_class:
		CharacterData.CharacterClass.MAGE: return SkillTree.make_mage_tree()
	return SkillTree.make_mage_tree()
