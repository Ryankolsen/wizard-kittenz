class_name ReviveSystem
extends RefCounted

# Half-HP revive at the location of death. Same shape as DamageResolver /
# PartyScaler — a stateless RefCounted with static helpers operating against
# duck-typed inputs (anything with hp:int + max_hp:int satisfies revive).

const REVIVE_HP_FRACTION: float = 0.5

# Sets player.hp to 50% of max_hp (rounded). The minimum-1 floor prevents
# the degenerate "max_hp=1 -> revive at 0" loop where the death screen
# would re-trigger immediately. Returns the resulting hp.
static func revive(player) -> int:
	if player == null:
		return 0
	var target := int(round(float(player.max_hp) * REVIVE_HP_FRACTION))
	target = maxi(1, target)
	player.hp = target
	return player.hp

# Spends one token from the inventory and revives the player. Returns true on
# success; false (with no mutation to player or inventory) when inventory is
# null or empty. Caller pattern: show death screen -> if try_consume_revive
# returns false, surface the "Buy More" path.
static func try_consume_revive(player, inventory: TokenInventory) -> bool:
	if inventory == null or player == null:
		return false
	if not inventory.spend(1):
		return false
	revive(player)
	return true
