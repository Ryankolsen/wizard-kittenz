class_name RoomRevealBridge
extends RefCounted

# Wires DungeonRunController.current_room_changed into FloorMapState.
# Pre-reveals the start room on bind() so the minimap chip shows the
# player's origin before any movement.
#
# Slice 1 of the minimap PRD (#304 / #305). Lives as RefCounted so the
# scene-layer owner (main_scene) controls lifetime — no add_child, no
# autoload.

var _controller: DungeonRunController = null
var _state: FloorMapState = null

func bind(controller: DungeonRunController, state: FloorMapState) -> void:
	if controller == null or state == null:
		return
	_controller = controller
	_state = state
	if controller.dungeon != null and controller.dungeon.start_id >= 0:
		state.mark_revealed(controller.dungeon.start_id)
	if not controller.current_room_changed.is_connected(_on_room_changed):
		controller.current_room_changed.connect(_on_room_changed)

func _on_room_changed(new_id: int) -> void:
	if _state == null:
		return
	_state.mark_revealed(new_id)
