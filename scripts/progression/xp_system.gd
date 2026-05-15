class_name XPSystem
extends RefCounted

# Awards XP to a party member. When use_real_level is true (the default),
# XP is added to real_stats so a level-10 player in a scaled party still
# earns progress toward their actual level. When false, XP applies to
# effective_stats — the seam for any future "scaled XP pool" mechanic.
# Returns the number of levels gained on the targeted stats.
#
# Optional `tree` (issue #124 follow-up): when supplied, level-gated
# SkillNodes whose `level_required` is now satisfied are auto-unlocked
# via the same path as the solo route. Null tree preserves the legacy
# behavior (XP applies, no unlock pass).
static func award(player, amount: int, use_real_level: bool = true, tree: SkillTree = null) -> int:
	if amount <= 0:
		return 0
	var target: CharacterData = player.real_stats if use_real_level else player.effective_stats
	if target == null:
		return 0
	return ProgressionSystem.add_xp(target, amount, null, tree)
