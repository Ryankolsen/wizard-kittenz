class_name PurchaseGrantHandler
extends RefCounted

# Dispatches a completed IAP into the concrete grant action for its product
# kind (class tier upgrade / cosmetic pack / class unlock / gem bundle /
# skill unlock). Stateless static surface so the rules can be exercised
# without booting GameState — the autoload only owns the signal wiring and
# the post-grant SaveManager.save call, not the dispatch itself.
#
# Returns true iff a grant was actually applied. The GameState wiring branches
# off this so a no-op replay (restore-purchases re-firing for an already-owned
# cosmetic, or a wrong-class upgrade product) doesn't trigger a redundant save.

static func handle(product_id: String, character: CharacterData,
		cosmetic_inventory: CosmeticInventory,
		paid_unlocks: PaidUnlockInventory = null,
		currency_ledger: CurrencyLedger = null,
		skill_inventory = null,
		item_inventory: ItemInventory = null,
		consumable_inventory: ConsumableInventory = null) -> bool:
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
		PurchaseRegistry.GRANT_GEM_BUNDLE:
			return _handle_gem_bundle(product_id, currency_ledger)
		PurchaseRegistry.GRANT_GEM_EXCHANGE:
			return _handle_gem_exchange(product_id, currency_ledger)
		PurchaseRegistry.GRANT_SKILL_UNLOCK:
			return _handle_skill_unlock(product_id, skill_inventory)
		PurchaseRegistry.GRANT_ITEM:
			return _handle_item(product_id, item_inventory)
		PurchaseRegistry.GRANT_POTION:
			return _handle_potion(product_id, consumable_inventory)
	return false

# Potion consumables (PRD #358 / slice 5). Each successful purchase adds 1 to
# the matching ConsumableInventory bucket — repeatable, no replay guard so
# buying twice yields count 2 (mirrors the gem-exchange semantics, unlike the
# one-time class/gear paths). Returns true iff the credit landed so the shop
# can refund the Gold debit on a null inventory / mis-routed product rather
# than silently eating the currency.
static func _handle_potion(product_id: String, consumable_inventory: ConsumableInventory) -> bool:
	if consumable_inventory == null:
		return false
	if PotionCatalog.find(product_id) == null:
		return false
	consumable_inventory.add(product_id, 1)
	return true

# Shop gear (PRD #201 / Slice 6). The product_id is the ItemCatalog id; we
# look the ItemData back up and append a fresh copy to the bag. Returns true
# iff the grant landed so the caller can refund a debit on a missing item /
# null inventory rather than silently eating Gold.
static func _handle_item(product_id: String, item_inventory: ItemInventory) -> bool:
	if item_inventory == null:
		return false
	var item_data := ItemCatalog.find(product_id)
	if item_data == null or item_data.source != ItemData.Source.SHOP:
		return false
	item_inventory.add_to_bag(item_data)
	return true

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

# Gem-bundle products credit the configured Gem amount against the active
# ledger. Replay guard lives on CurrencyLedger.try_grant_bundle so a second
# purchase_succeeded for the same bundle (BillingManager re-firing on
# startup before the consume-acknowledge lands) is a no-op.
static func _handle_gem_bundle(product_id: String,
		currency_ledger: CurrencyLedger) -> bool:
	if currency_ledger == null:
		return false
	var amount := PurchaseRegistry.gem_amount_for(product_id)
	if amount <= 0:
		return false
	return currency_ledger.try_grant_bundle(product_id, amount)

# Gem-exchange products ("convert diamonds to money") credit the configured
# Gold amount. The matching Gem debit is the caller's job — ShopScreen's
# soft-currency path debits item.price (Gems) before calling handle(), so this
# only mints the Gold half. No replay guard: an exchange is a repeatable
# consumable, not a one-time grant. Returns true iff Gold was credited so the
# caller can refund the Gem debit on a null ledger / mis-routed product.
static func _handle_gem_exchange(product_id: String,
		currency_ledger: CurrencyLedger) -> bool:
	if currency_ledger == null:
		return false
	var gold := PurchaseRegistry.gold_amount_for(product_id)
	if gold <= 0:
		return false
	currency_ledger.credit(gold, CurrencyLedger.Currency.GOLD)
	return true

# Skill-unlock products grant a permanent skill entry. Mirrors the class-unlock
# path but routes into SkillInventory (#71's eventual SkillTree consults this
# as an OR'd path next to the in-game unlock gate). Null inventory is a safe
# no-op so legacy call sites without a skill inventory pre-wired don't crash.
static func _handle_skill_unlock(product_id: String, skill_inventory) -> bool:
	if skill_inventory == null:
		return false
	var skill_id := PurchaseRegistry.skill_id_for_unlock(product_id)
	if skill_id == "":
		return false
	return skill_inventory.grant(skill_id)

static func _handle_class_upgrade(product_id: String, character: CharacterData) -> bool:
	if character == null:
		return false
	var source_class := PurchaseRegistry.class_for_product(product_id)
	if int(character.character_class) != source_class:
		return false
	if not ClassTierUpgrade.has_upgrade(character.character_class):
		# Product exists in the catalog but ClassTierUpgrade.TIER_MAP doesn't
		# route the source class. Surface as no-op so the shop UI can show a
		# "coming soon" affordance instead of mutating state.
		return false
	return ClassTierUpgrade.upgrade(character)
