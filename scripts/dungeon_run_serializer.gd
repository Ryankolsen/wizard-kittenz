class_name DungeonRunSerializer
extends RefCounted

# Save/restore for an active DungeonRunController (PRD #42, #46). Pure static —
# no scene tree, no autoload — so the (de)serialize halves are exercised by
# unit tests without a fixture.
#
# State shape:
#   {
#     "seed": <int>,                  # the seed fed to DungeonGenerator.generate
#     "current_room_id": <int>,       # controller.current_room_id at save time
#     "cleared_room_ids": [<int>...]  # explicitly cleared rooms only
#   }
#
# Auto-cleared rooms (start, power-up) aren't persisted — they re-derive from
# the regenerated dungeon's room types on restore, so storing them would be
# redundant and would risk drifting away from the layout's truth.
#
# The seed is stored separately (not inferred from the controller) because
# Dungeon doesn't carry its source seed — the generator hands back a fresh
# Dungeon with no provenance. Callers thread the seed through at save time.

static func serialize(controller: DungeonRunController, seed: int) -> Dictionary:
	if controller == null or controller.dungeon == null:
		return {}
	return {
		"seed": seed,
		"current_room_id": controller.current_room_id,
		"cleared_room_ids": controller.cleared_ids(),
	}

# Rebuilds a DungeonRunController from a state dict. Regenerates the dungeon
# from the saved seed, advances the controller to the saved current_room_id,
# and replays mark_room_cleared for each persisted cleared room.
#
# Returns null on empty / malformed state — the caller should treat that as
# "no resumable run" and call _start_new_dungeon instead. This is the legacy-
# save path: KittenSaveData.from_dict defaults dungeon_run_state to {} for
# saves predating the field, and a missing seed is the sentinel.
static func deserialize(state: Dictionary) -> DungeonRunController:
	if state.is_empty():
		return null
	if not state.has("seed"):
		return null
	var seed := int(state.get("seed", -1))
	var dungeon := DungeonGenerator.generate(seed)
	var controller := DungeonRunController.new()
	if not controller.start(dungeon):
		return null
	controller.seed = seed
	# Replay clears before snapping current_room_id so mark_room_cleared's
	# advanced-into guard (if any future check were added) wouldn't reject a
	# clear for a room the player isn't standing in.
	var cleared = state.get("cleared_room_ids", [])
	if cleared is Array:
		for raw in cleared:
			controller.mark_room_cleared(int(raw))
	controller.current_room_id = int(state.get("current_room_id", dungeon.start_id))
	return controller
