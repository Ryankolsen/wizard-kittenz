class_name PurchaseGrantHandler
extends RefCounted

# Dispatches a completed IAP into the concrete grant action for its product
# kind (class tier upgrade / cosmetic pack / class unlock). Stateless static
# surface so the rules can be exercised without booting GameState — the
# autoload only owns the signal wiring and the post-grant SaveManager.save
# call, not the dispatch itself.
#
# Returns true iff a grant was actually applied. The GameState wiring branches
# off this so a no-op replay (restore-purchases re-firing for an already-owned
# cosmetic, or a wrong-class upgrade product) doesn't trigger a redundant save.

static func handle(product_id: String, character: CharacterData,
		cosmetic_inventory: CosmeticInventory,
		paid_unlocks: PaidUnlockInventory = null) -> bool:
	var grant_type := PurchaseRegistry.grant_type_for(product_id)
	match grant_type:
		PurchaseRegistry.GRANT_CLASS_UPGRADE:
			return _handle_class_upgrade(product_id, character)
		PurchaseRegistry.GRANT_COSMETIC_PACK:
			if cosmetic_inventory == null:
				return false
			return cosmetic_inventory.grant(product_id)
		PurchaseRegistry.GRANT_CLASS_UNLOCK:
			return _handle_class_unlock(product_id, paid_unlocks)
	return false

# Class-unlock products grant a permanent paid unlock entry consulted by
# UnlockRegistry.is_unlocked as an OR'd path alongside the gameplay condition
# gates (PRD #26 "earnable through gameplay OR purchased"). Null inventory is
# a defensive skip — call sites without paid_unlocks pre-wired fall through to
# the prior "no-op true" behavior so a replay during restore-purchases doesn't
# loop without a save target. Returns true iff the grant landed on this call
# (false on replay so GameState's signal handler skips the redundant save).
static func _handle_class_unlock(product_id: String,
		paid_unlocks: PaidUnlockInventory) -> bool:
	if paid_unlocks == null:
		return false
	var class_id := PurchaseRegistry.class_id_for_unlock(product_id)
	if class_id == "":
		return false
	return paid_unlocks.grant(class_id)

static func _handle_class_upgrade(product_id: String, character: CharacterData) -> bool:
	if character == null:
		return false
	var source_class := PurchaseRegistry.class_for_product(product_id)
	if int(character.character_class) != source_class:
		return false
	if not ClassTierUpgrade.has_upgrade(character.character_class):
		# Product exists in the catalog (e.g. UPGRADE_THIEF_MASTER_THIEF) but
		# ClassTierUpgrade.TIER_MAP doesn't yet route it. Surface as no-op so
		# the shop UI can show a "coming soon" affordance instead of mutating
		# state. See PurchaseRegistry catalog notes.
		return false
	return ClassTierUpgrade.upgrade(character)
