class_name ReviveSystem
extends RefCounted

# Free half-HP revive at the location of death. Stateless RefCounted with a
# single static helper operating against duck-typed inputs (anything with
# hp:int + max_hp:int satisfies revive).
#
# Free-revive contract (post-#27): no token gate, no inventory dependency.
# The monetization seam shifted to permanent upgrades (#26 PRD); reviving is
# always available so a death never ends a co-op session.

const REVIVE_HP_FRACTION: float = 0.5

# Sets player.hp to 50% of max_hp (rounded). The minimum-1 floor prevents
# the degenerate "max_hp=1 -> revive at 0" loop where the death screen
# would re-trigger immediately. Returns the resulting hp; 0 when player is
# null (test / pre-spawn path).
static func revive(player) -> int:
	if player == null:
		return 0
	var target := int(round(float(player.max_hp) * REVIVE_HP_FRACTION))
	target = maxi(1, target)
	player.hp = target
	return player.hp
