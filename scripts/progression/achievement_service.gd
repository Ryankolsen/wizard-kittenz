class_name AchievementService
extends RefCounted

# Engine core for achievements (PRD #446 / issue #447). The single entry
# point gameplay code calls is record_event(event_key) — it doesn't know or
# care which (if any) achievements are bound to that event, keeping
# dungeon/chest/combat code decoupled from achievement content.
#
# Bound to one AccountSaveData for its lifetime (account-wide state, shared
# across all 4 character slots) so an achievement earned on one cat is
# locked out for the others. active_slot is set by the caller whenever the
# active character changes, and is captured into each newly-unlocked entry
# so claim() (issue #448) can route potion rewards to the cat that actually
# earned them, even if the player has since switched slots.

signal achievement_unlocked(id: String)

var account: AccountSaveData
var catalog: Array
var active_slot: String = ""

func _init(p_account: AccountSaveData, p_catalog: Array = AchievementCatalog.all()) -> void:
	account = p_account
	catalog = p_catalog

# Unlocks every catalog definition bound to event_key that isn't already in
# account.achievement_state. Already-unlocked ids are a no-op (does not
# touch unlocked_at/earned_by_slot). Unknown/unbound event keys are a safe
# no-op. Emits achievement_unlocked once per newly-unlocked id.
func record_event(event_key: String) -> void:
	if account == null or event_key == "":
		return
	for definition in catalog:
		if definition.trigger_event != event_key:
			continue
		if account.achievement_state.has(definition.id):
			continue
		account.achievement_state[definition.id] = {
			"unlocked_at": Time.get_unix_time_from_system(),
			"claimed": false,
			"earned_by_slot": active_slot,
		}
		achievement_unlocked.emit(definition.id)

# Adds amount to account.achievement_counters[counter_key] (account-wide,
# shared across all slots), then unlocks any tiered catalog definition bound
# to that counter_key whose threshold is newly met. Same idempotency/dedup
# and earned_by_slot capture as record_event.
func increment_counter(counter_key: String, amount: int) -> void:
	if account == null or counter_key == "":
		return
	var total := int(account.achievement_counters.get(counter_key, 0)) + amount
	account.achievement_counters[counter_key] = total
	for definition in catalog:
		if definition.counter_key != counter_key:
			continue
		if total < definition.threshold:
			continue
		if account.achievement_state.has(definition.id):
			continue
		account.achievement_state[definition.id] = {
			"unlocked_at": Time.get_unix_time_from_system(),
			"claimed": false,
			"earned_by_slot": active_slot,
		}
		achievement_unlocked.emit(definition.id)

# Grants an unlocked-but-unclaimed achievement's fixed reward and marks it
# claimed (issue #448). Gold routes account-wide via currency_ledger. Potions,
# items, and tomes all route to the earning entry's earned_by_slot — the live
# consumable_inventory/item_inventory/skill_tree+quickbar when that slot is
# the currently active one, otherwise directly into bundle's matching
# CharacterSlotData (consumable_inventory_data / item_bag /
# unlocked_skill_ids+quickbar_slots; an inactive slot has no live
# inventory/skill tree to hydrate). Returns the claimed AchievementDefinition
# (for UI reward/flavor display), or null on any safe no-op: unknown id,
# never unlocked, or already claimed.
func claim(id: String, currency_ledger: CurrencyLedger = null, consumable_inventory: ConsumableInventory = null, bundle: SaveBundle = null, item_inventory: ItemInventory = null, skill_tree: SkillTree = null, quickbar: Quickbar = null) -> AchievementDefinition:
	if account == null:
		return null
	var entry = account.achievement_state.get(id)
	if not (entry is Dictionary) or bool(entry.get("claimed", false)):
		return null
	var definition: AchievementDefinition = null
	for d in catalog:
		if d.id == id:
			definition = d
			break
	if definition == null:
		return null
	if definition.reward_type == AchievementDefinition.RewardType.GOLD:
		if currency_ledger != null:
			currency_ledger.credit(definition.reward_amount, CurrencyLedger.Currency.GOLD)
	elif definition.reward_type == AchievementDefinition.RewardType.ITEM:
		var earned_slot := String(entry.get("earned_by_slot", ""))
		if earned_slot == active_slot and item_inventory != null:
			item_inventory.add_to_bag(ItemCatalog.find(definition.reward_item_id))
		elif bundle != null:
			var slot: CharacterSlotData = bundle.get_slot(earned_slot)
			if slot != null:
				slot.item_bag.append(definition.reward_item_id)
	elif definition.reward_type == AchievementDefinition.RewardType.TOME:
		var earned_slot := String(entry.get("earned_by_slot", ""))
		if earned_slot == active_slot and skill_tree != null and quickbar != null:
			skill_tree.unlock(definition.reward_node_id)
			var node := skill_tree.find(definition.reward_node_id)
			if node != null and node.spell != null:
				quickbar.on_spell_unlocked(node.spell)
		elif bundle != null:
			var slot: CharacterSlotData = bundle.get_slot(earned_slot)
			if slot != null:
				_grant_tome_to_slot_data(slot, definition.reward_node_id, definition.reward_spell_id)
	elif definition.reward_type == AchievementDefinition.RewardType.NONE:
		pass
	else:
		var earned_slot := String(entry.get("earned_by_slot", ""))
		if earned_slot == active_slot and consumable_inventory != null:
			consumable_inventory.add(definition.reward_potion_id, definition.reward_amount)
		elif bundle != null:
			var slot: CharacterSlotData = bundle.get_slot(earned_slot)
			if slot != null:
				var current := int(slot.consumable_inventory_data.get(definition.reward_potion_id, 0))
				slot.consumable_inventory_data[definition.reward_potion_id] = mini(current + definition.reward_amount, ConsumableInventory.STACK_CAP)
	entry["claimed"] = true
	account.achievement_state[id] = entry
	return definition

# TOME's inactive-slot path: no live SkillTree/Quickbar exists to hydrate, so
# the unlock/assignment is mirrored directly onto the raw CharacterSlotData
# fields those two would otherwise have written on save (see
# CharacterSlotData.from_state). unlocked_skill_ids is an unordered set, same
# as item_bag's append; quickbar_slots is positional, so this reproduces
# Quickbar.on_spell_unlocked's "lowest empty slot, no-op if already assigned"
# behavior against the raw id array instead of live Spell objects.
func _grant_tome_to_slot_data(slot: CharacterSlotData, node_id: String, spell_id: String) -> void:
	if not slot.unlocked_skill_ids.has(node_id):
		slot.unlocked_skill_ids.append(node_id)
	if slot.quickbar_slots.has(spell_id):
		return
	for i in range(Quickbar.SLOT_COUNT):
		if i >= slot.quickbar_slots.size():
			slot.quickbar_slots.append(spell_id)
			return
		if slot.quickbar_slots[i] == "":
			slot.quickbar_slots[i] = spell_id
			return
