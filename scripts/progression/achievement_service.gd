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
# claimed (issue #448). Gold routes account-wide via currency_ledger. Potions
# route to the ConsumableInventory belonging to the entry's earned_by_slot —
# consumable_inventory when that slot is the currently active one, otherwise
# directly into bundle's matching CharacterSlotData.consumable_inventory_data
# (an inactive slot has no live ConsumableInventory to hydrate). Returns the
# claimed AchievementDefinition (for UI reward/flavor display), or null on any
# safe no-op: unknown id, never unlocked, or already claimed.
func claim(id: String, currency_ledger: CurrencyLedger = null, consumable_inventory: ConsumableInventory = null, bundle: SaveBundle = null) -> AchievementDefinition:
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
