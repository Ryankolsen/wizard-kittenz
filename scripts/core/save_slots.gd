class_name SaveSlots
extends RefCounted

# Slot registry over a SaveBundle (PRD #250 / slice 3). Pure-data helper:
# query slot occupancy/summary, build a fresh CharacterSlotData for a new
# game, and wipe a slot back to empty without touching AccountSaveData.
#
# The four archetype slot keys live on SaveBundle (SLOT_BATTLE / _WIZARD /
# _SLEEPY / _CHONK). slot_summaries iterates them in a stable order so the
# character-select grid (#254) can bind cards by index.

const ARCHETYPES := [
	SaveBundle.SLOT_BATTLE,
	SaveBundle.SLOT_WIZARD,
	SaveBundle.SLOT_SLEEPY,
	SaveBundle.SLOT_CHONK,
]

# Kitten enum value for each archetype slot key. Used by create_slot to spin
# up a level-1 character of the right class for that slot.
static func _kitten_class_for(archetype: String) -> int:
	match archetype:
		SaveBundle.SLOT_BATTLE: return CharacterData.CharacterClass.BATTLE_KITTEN
		SaveBundle.SLOT_WIZARD: return CharacterData.CharacterClass.WIZARD_KITTEN
		SaveBundle.SLOT_SLEEPY: return CharacterData.CharacterClass.SLEEPY_KITTEN
		SaveBundle.SLOT_CHONK: return CharacterData.CharacterClass.CHONK_KITTEN
	return CharacterData.CharacterClass.BATTLE_KITTEN

static func is_occupied(bundle: SaveBundle, archetype: String) -> bool:
	if bundle == null:
		return false
	return bundle.get_slot(archetype) != null

# Stable-order summary for the character-select grid. Empty slots report
# occupied = false with neutral name/level/class fields so the UI can render
# an "empty" card by checking the flag without null-handling everywhere.
static func slot_summaries(bundle: SaveBundle) -> Array:
	var out: Array = []
	for archetype in ARCHETYPES:
		var slot: CharacterSlotData = bundle.get_slot(archetype) if bundle != null else null
		if slot == null:
			out.append({
				"archetype": archetype,
				"occupied": false,
				"name": "",
				"level": 0,
				"class": _kitten_class_for(archetype),
			})
		else:
			out.append({
				"archetype": archetype,
				"occupied": true,
				"name": slot.character_name,
				"level": slot.level,
				"class": slot.character_class,
			})
	return out

static func create_slot(archetype: String, character_name: String) -> CharacterSlotData:
	var klass := _kitten_class_for(archetype)
	var c := CharacterData.make_new(klass, character_name)
	return CharacterSlotData.from_state(c)

# Wipe the archetype's slot back to a fresh level-1 Kitten of that archetype.
# Account-wide fields (gold/gems/unlocks/cosmetics/meta/streak) are explicitly
# untouched per PRD #250 user story 7. The slot's existing name is preserved
# so "Restart" feels like the same character starting over, not a renamed one.
static func new_game_reset(bundle: SaveBundle, archetype: String) -> void:
	if bundle == null:
		return
	var prior: CharacterSlotData = bundle.get_slot(archetype)
	var prior_name := prior.character_name if prior != null else "Kitten"
	var fresh := create_slot(archetype, prior_name)
	bundle.slots[archetype] = fresh
