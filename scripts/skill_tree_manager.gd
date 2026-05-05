class_name SkillTreeManager
extends RefCounted

# Validates and applies skill-tree unlocks against a CharacterData's skill-point
# budget. Modeled as a stateful instance over (tree, character) so the call
# sites read like `manager.unlock("fireball")` per the issue spec, while the
# underlying mutation stays in one place.

var tree: SkillTree = null
var character: CharacterData = null

static func make(t: SkillTree, c: CharacterData) -> SkillTreeManager:
	var m := SkillTreeManager.new()
	m.tree = t
	m.character = c
	return m

# can_unlock returns false (without mutating state) if any of: node missing,
# already unlocked, prereq locked, or insufficient points. unlock() only
# proceeds when can_unlock is true so a failed attempt is guaranteed not to
# touch character.skill_points or node.unlocked.
func can_unlock(node_id: String) -> bool:
	if tree == null or character == null:
		return false
	var node := tree.find(node_id)
	if node == null or node.unlocked:
		return false
	if character.skill_points < node.cost:
		return false
	for prereq_id in node.prerequisite_ids:
		var p := tree.find(prereq_id)
		if p == null or not p.unlocked:
			return false
	return true

func unlock(node_id: String) -> bool:
	if not can_unlock(node_id):
		return false
	var node := tree.find(node_id)
	node.unlocked = true
	character.skill_points -= node.cost
	return true
