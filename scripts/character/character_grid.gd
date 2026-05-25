class_name CharacterGrid
extends RefCounted

# Pure helpers behind the character-select grid + name-only customize flow
# (PRD #250 / issue #254). The scene wiring lives in character_creation.gd;
# this file extracts the pieces that don't need a tree so they can be unit-
# tested without spinning up the UI.

# class_name lookup of sibling helpers is load-order-fragile in fresh test
# files (see GameState's preload pattern); preload SaveSlots so this script
# parses without depending on the global class registry being warm.
const _SaveSlotsRef = preload("res://scripts/core/save_slots.gd")

# Card label for a SaveSlots.slot_summaries() entry. Occupied → "Name · Lv N";
# empty → "New". UI binds one of these per archetype card.
static func card_label(summary: Dictionary) -> String:
	if not summary.get("occupied", false):
		return "New"
	return "%s · Lv %d" % [String(summary.get("name", "")), int(summary.get("level", 1))]

# Name-only customize result. Delegates to SaveSlots.create_slot, which spins
# a level-1 character of the archetype's Kitten class — appearance_index
# defaults to 0 (CharacterSlotData default) since the appearance picker was
# removed in slice 4.
static func customize_create_slot(archetype: String, character_name: String) -> CharacterSlotData:
	return _SaveSlotsRef.create_slot(archetype, character_name)

# New-Game-confirmed handler. Thin wrapper over SaveSlots.new_game_reset so
# the scene layer can call a single intention-named function and tests can
# assert on bundle state without needing the confirmation panel.
static func confirm_new_game(bundle: SaveBundle, archetype: String) -> void:
	_SaveSlotsRef.new_game_reset(bundle, archetype)
