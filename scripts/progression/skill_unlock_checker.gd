class_name SkillUnlockChecker
extends RefCounted

# Centralized helper for the PRD #124 / issue #126 level-gated auto-unlock rule:
# any SkillNode with `level_required <= level` becomes unlocked, no skill-point
# spend required. Keeps ProgressionSystem (stateless, character-only) decoupled
# from SkillTree (per-class graph) — both sides call into this helper rather
# than knowing about each other directly.
#
# Idempotent: nodes already unlocked are skipped, so calling repeatedly across
# multiple level-ups (or once on character creation and again on every level-up)
# doesn't double-process. Returns the ids that flipped from locked -> unlocked
# this call, so a future UI / SFX hook can react to fresh unlocks specifically
# without diffing the tree itself.
static func auto_unlock_for_level(tree: SkillTree, level: int) -> Array:
	var newly: Array = []
	if tree == null:
		return newly
	for n in tree.all_nodes():
		if not n.unlocked and n.level_required <= level:
			n.unlocked = true
			newly.append(n.id)
	return newly
