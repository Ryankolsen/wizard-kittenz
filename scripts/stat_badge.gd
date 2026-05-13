class_name StatBadge
extends RefCounted

# Pure predicate for the unspent-stat-points badge (#58, PRD #52). The HUD
# and pause-menu Stats tab both read the same rule — surface this as a
# static helper so the visibility contract is unit-testable without a
# scene tree. Mirrors HUD.xp_bar_ratio / DamageResolver shape.
#
# Returns true iff there are skill_points to spend. Negative inputs (a
# defensive contract: should never happen, but a stale save dict or a
# half-built CharacterData could in principle reach this surface) are
# treated as "no badge."

static func should_show(skill_points: int) -> bool:
	return skill_points > 0
