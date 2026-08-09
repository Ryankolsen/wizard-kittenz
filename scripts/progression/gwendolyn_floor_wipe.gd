class_name GwendolynFloorWipe
extends RefCounted

# Pure filtering logic for the Summon Gwendolyn cast payoff (issue #478).
# Given every enemy currently spawned on the floor, returns the subset that
# the floor-wipe kill effect should apply to: everything except the boss.
# Kept as a stateless static so the scene-level wiring (Player) can gather
# enemy data however it wants (get_tree().get_nodes_in_group("enemies"))
# without this resolver needing a scene tree.

static func non_boss_kills(enemies: Array) -> Array:
	var out: Array = []
	for e in enemies:
		if e != null and not e.is_boss:
			out.append(e)
	return out
