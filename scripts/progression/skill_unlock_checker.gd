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
#
# `character_class` (PRD #418 / issue #420): defaults to -1 ("unknown"), which
# preserves legacy behavior for callers that only pass level. A node whose
# `required_class` is set only unlocks when it matches this value, so a
# never-evolved Kitten can't unlock Cat-tier nodes by leveling alone even if
# the tree it holds somehow contained one.
static func auto_unlock_for_level(tree: SkillTree, level: int, character_class: int = -1) -> Array:
	var newly: Array = []
	if tree == null:
		return newly
	for n in tree.all_nodes():
		if n.unlocked:
			continue
		if n.level_required > level:
			continue
		if n.required_class != -1 and n.required_class != character_class:
			continue
		n.unlocked = true
		newly.append(n.id)
	return newly
