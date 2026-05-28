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

# Human-readable class name for a CharacterData.CharacterClass enum value, e.g.
# WIZARD_KITTEN → "Wizard Kitten". Mirrors pause_menu's class-label derivation
# so the card grid and the in-game HUD speak the same names.
static func class_display_name(klass: int) -> String:
	var idx := CharacterData.CharacterClass.values().find(klass)
	if idx == -1:
		return ""
	var raw: String = CharacterData.CharacterClass.keys()[idx]
	return raw.replace("_", " ").to_lower().capitalize()

# Card title line: the character's name when occupied, else the "New Game" prompt.
static func card_name_text(summary: Dictionary) -> String:
	if not summary.get("occupied", false):
		return "New Game"
	return String(summary.get("name", ""))

# Card class line: the archetype's display name, shown for occupied and empty
# slots alike so every card advertises its class.
static func card_class_text(summary: Dictionary) -> String:
	return class_display_name(int(summary.get("class", 0)))

# Card level line: "Lv N" for occupied slots, blank for empty ones.
static func card_level_text(summary: Dictionary) -> String:
	if not summary.get("occupied", false):
		return ""
	return "Lv %d" % int(summary.get("level", 1))

# res:// path to the portrait sprite for an archetype slot key. Reuses the
# in-dungeon right-facing kitten sprites so the grid needs no new art. The
# scene bakes these textures directly; this mapping keeps them documented and
# testable in one place.
static func sprite_path_for(archetype: String) -> String:
	match archetype:
		SaveBundle.SLOT_BATTLE: return "res://assets/sprites/battle_kitten_right.png"
		SaveBundle.SLOT_WIZARD: return "res://assets/sprites/wizard_kitten_right.png"
		SaveBundle.SLOT_SLEEPY: return "res://assets/sprites/sleepy_kitten_right.png"
		SaveBundle.SLOT_CHONK: return "res://assets/sprites/chonk_kitten_right.png"
	return ""

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
