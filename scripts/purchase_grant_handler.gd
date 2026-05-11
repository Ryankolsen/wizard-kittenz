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
		cosmetic_inventory: CosmeticInventory) -> bool:
	var grant_type := PurchaseRegistry.grant_type_for(product_id)
	match grant_type:
		PurchaseRegistry.GRANT_CLASS_UPGRADE:
			return _handle_class_upgrade(product_id, character)
		PurchaseRegistry.GRANT_COSMETIC_PACK:
			if cosmetic_inventory == null:
				return false
			return cosmetic_inventory.grant(product_id)
		PurchaseRegistry.GRANT_CLASS_UNLOCK:
			# Stub: UnlockRegistry is gameplay-gated today (e.g. archmage
			# requires max_level_per_class.mage >= 5). When a paid unlock path
			# lands it'll mutate UnlockRegistry or a sibling registry. For now
			# we return true so BillingManager's acknowledgement path treats
			# the purchase as handled rather than looping on it.
			return true
	return false

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
