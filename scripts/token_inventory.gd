class_name TokenInventory
extends RefCounted

# Persistent counter of revive tokens. Stays a thin RefCounted (not a Resource)
# so it shares the JSON-projection lane with KittenSaveData rather than the
# .tres-shaped CharacterData lane — saves can evolve the field set without a
# resource migration. Same pattern as MetaProgressionTracker.

var count: int = 0

# Returns true when `amount` tokens were available and got debited; false
# (with no mutation) when the inventory is short. Negative/zero amounts are
# rejected as no-ops so a future "free revive" debuff path can't accidentally
# add tokens by spending negatives.
func spend(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	if count < amount:
		return false
	count -= amount
	return true

# Adds `amount` tokens to the inventory. Returns the actual amount granted
# (0 for non-positive inputs) so callers can decide whether to surface a
# "+N tokens" toast.
func grant(amount: int) -> int:
	if amount <= 0:
		return 0
	count += amount
	return amount

func to_dict() -> Dictionary:
	return {"count": count}

static func from_dict(d: Dictionary) -> TokenInventory:
	var t := TokenInventory.new()
	t.count = int(d.get("count", 0))
	return t
