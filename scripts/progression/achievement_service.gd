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
