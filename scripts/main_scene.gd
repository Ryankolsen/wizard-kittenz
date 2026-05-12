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
	var dungeon := DungeonGenerator.generate(_dungeon_seed_for(gs))
	_run_controller = DungeonRunController.new()
	_run_controller.start(dungeon)
	if gs != null:
		gs.dungeon_run_controller = _run_controller

# Co-op clients converge on the host's minted seed via DungeonSeedSync, so all
# party members generate identical room graphs. Solo path / no agreed seed
# falls through to -1 (DungeonGenerator's randomize-on-negative sentinel) so a
# fresh dungeon rolls each run. Reads the seed sync via coop_session, which
# holds the borrowed reference the lobby handed in at match-start.
func _dungeon_seed_for(gs) -> int:
	if gs == null or gs.coop_session == null:
		return -1
	var seed_sync: DungeonSeedSync = gs.coop_session.dungeon_seed_sync
	if seed_sync == null or not seed_sync.is_agreed():
		return -1
	return seed_sync.current_seed()

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
	# is_dungeon_complete() is already true when this fires for the boss room
	# (_cleared[boss_id] is set before room_cleared.emit). Let dungeon_completed
	# handle that case; show the button for every other cleared room.
	if _run_controller.is_dungeon_complete():
		return
	_hud.show_next_room_prompt()

func _on_next_room_requested() -> void:
	var next_id := _next_room_toward_boss()
	if next_id < 0:
		return
	_run_controller.advance_to(next_id)
	get_tree().reload_current_scene()

# Returns the id of the best next room to advance to: the first connection
# from which the boss is reachable (BFS). Skips dead-end branches so the
# player never ends up in a non-boss leaf room. Falls back to connections[0]
# only if every branch leads nowhere — which a valid spanning-tree dungeon
# prevents by construction.
func _next_room_toward_boss() -> int:
	var room := _run_controller.current_room()
	if room == null or room.connections.is_empty():
		return -1
	var boss_id := _run_controller.dungeon.boss_id
	for conn_id in room.connections:
		if conn_id == boss_id or _can_reach(conn_id, boss_id):
			return conn_id
	return room.connections[0]

func _can_reach(from_id: int, target_id: int) -> bool:
	var dungeon := _run_controller.dungeon
	var visited := {}
	var queue := [from_id]
	while not queue.is_empty():
		var id: int = queue.pop_front()
		if id == target_id:
			return true
		if visited.has(id):
			continue
		visited[id] = true
		var r := dungeon.get_room(id)
		if r == null:
			continue
		for next_id in r.connections:
			if not visited.has(next_id):
				queue.append(next_id)
	return false

func _on_dungeon_completed() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		DungeonRunCompletion.complete(gs.meta_tracker)
		gs.dungeon_run_controller = null
	get_tree().reload_current_scene()
