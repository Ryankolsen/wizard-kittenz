class_name AchievementBadge
extends RefCounted

# Pure predicate for the pause-button achievement badge (#450, PRD #446).
# Mirrors StatBadge.should_show's shape so the visibility contract is
# unit-testable without a scene tree.
#
# Returns true iff achievement_state has at least one unlocked-and-unclaimed
# entry (claimed == false). Empty dict returns false.

static func should_show(achievement_state: Dictionary) -> bool:
	for entry in achievement_state.values():
		if not bool(entry.get("claimed", false)):
			return true
	return false
