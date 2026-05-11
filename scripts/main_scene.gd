extends Node2D

# Scene-layer orchestrator for the main dungeon room. Bridges the pure-data
# layer (DungeonRunController + RoomClearWatcher) to the scene tree:
#   - Initializes or resumes the dungeon run from GameState (survives reloads).
#   - Assigns per-room EnemyData from RoomSpawnPlanner to the Enemy node so
#     enemy_id, kind, and is_boss are correct for the current room.
#   - Wires Enemy.died -> RoomClearWatcher.notify_death so the kill flow
#     drives DungeonRunController.mark_room_cleared.
#   - Listens for room_cleared -> shows the "Next Room" prompt on the HUD.
#   - Advances to the next room (via advance_to + scene reload) on button press.
#   - Handles dungeon_completed (boss killed): calls DungeonRunCompletion,
#     clears run state, and reloads for a new dungeon.
#
# No-enemy rooms (start, power-up): enemy node is freed on enter; the watcher
# auto-clears immediately and the Next Room prompt appears without combat.

var _run_controller: DungeonRunController = null
var _watcher: RoomClearWatcher = null
var _hud: HUD = null
var _enemy: Enemy = null

func _ready() -> void:
	_hud = $HUD
	_enemy = $Enemy

	var gs := get_node_or_null("/root/GameState")

	if gs == null or gs.dungeon_run_controller == null:
		_start_new_dungeon(gs)
	else:
		_run_controller = gs.dungeon_run_controller

	# Connect before _setup_current_room so auto-clear rooms get the signal.
	_run_controller.room_cleared.connect(_on_room_cleared)
	_run_controller.dungeon_completed.connect(_on_dungeon_completed)
	_hud.next_room_requested.connect(_on_next_room_requested)

	_setup_current_room()

func _start_new_dungeon(gs) -> void:
	var dungeon := DungeonGenerator.generate()
	_run_controller = DungeonRunController.new()
	_run_controller.start(dungeon)
	if gs != null:
		gs.dungeon_run_controller = _run_controller

func _setup_current_room() -> void:
	var room := _run_controller.current_room()
	if room == null:
		return

	var enemy_data := RoomSpawnPlanner.plan_enemy(room)
	if enemy_data == null:
		# No combat in this room — remove the enemy so the HUD counts zero.
		if _enemy != null:
			_enemy.queue_free()
			_enemy = null
	else:
		if _enemy != null:
			_enemy.data = enemy_data
			_enemy.died.connect(_on_enemy_died)

	_watcher = RoomClearWatcher.new()
	_watcher.watch(room, _run_controller)

func _on_enemy_died() -> void:
	if _enemy == null or _enemy.data == null:
		return
	_watcher.notify_death(_enemy.data.enemy_id)

func _on_room_cleared(_room_id: int) -> void:
	var room := _run_controller.current_room()
	# Boss room has no connections — dungeon_completed fires right after;
	# skip the Next Room button so a stale prompt doesn't flash before reload.
	if room == null or room.connections.is_empty():
		return
	_hud.show_next_room_prompt()

func _on_next_room_requested() -> void:
	var room := _run_controller.current_room()
	if room == null or room.connections.is_empty():
		return
	_run_controller.advance_to(room.connections[0])
	get_tree().reload_current_scene()

func _on_dungeon_completed() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		DungeonRunCompletion.complete(gs.meta_tracker, gs.token_inventory)
		gs.dungeon_run_controller = null
	get_tree().reload_current_scene()
