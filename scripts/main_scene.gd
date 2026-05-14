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
var _dungeon_layout: DungeonLayout = null

func _ready() -> void:
	_hud = $HUD
	_enemy = $Enemy

	var gs := get_node_or_null("/root/GameState")

	if gs == null or gs.dungeon_run_controller == null:
		_start_new_dungeon(gs)
	else:
		_run_controller = gs.dungeon_run_controller

	_paint_dungeon()

	# Connect before _setup_current_room so auto-clear rooms get the signal.
	_run_controller.room_cleared.connect(_on_room_cleared)
	_run_controller.dungeon_completed.connect(_on_dungeon_completed)
	_run_controller.dungeon_transitioned.connect(_on_dungeon_transitioned)
	_hud.next_room_requested.connect(_on_next_room_requested)

	_setup_current_room()

# Computes the spatial layout from the active dungeon graph and paints the
# full multi-room tilemap (rooms + corridors + walls). The layout is cached
# so future renderers (exit door placement, room-bound camera) can read it
# without recomputing. Camera limits clamp to the painted extents so the
# camera never reveals void past the dungeon walls.
func _paint_dungeon() -> void:
	if _run_controller == null or _run_controller.dungeon == null:
		return
	var tilemap: TileMap = $TileMap
	if tilemap == null:
		return
	_dungeon_layout = DungeonLayoutEngine.new().compute(_run_controller.dungeon)
	var painter := DungeonTilemapPainter.new()
	painter.paint(_dungeon_layout, tilemap, _run_controller.dungeon)
	var player := get_node_or_null("Player")
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			DungeonTilemapPainter.apply_camera_limits(camera, tilemap)

func _start_new_dungeon(gs) -> void:
	var seed := _dungeon_seed_for(gs)
	var dungeon := DungeonGenerator.generate(seed)
	_run_controller = DungeonRunController.new()
	_run_controller.start(dungeon)
	_run_controller.seed = seed
	if gs != null:
		gs.dungeon_run_controller = _run_controller
		# Co-op session activation. Before this commit, lobby.gd's
		# _on_match_started constructed CoopSession but never start()'d
		# it — so session.enemy_sync, xp_broadcaster, and
		# position_broadcast_gate stayed null and every wire-layer flow
		# (kill XP fan-out, position broadcast, remote-kill receive)
		# silently no-op'd because is_coop_route / null-gate checks
		# returned false. Activating here, after the dungeon is generated,
		# gives the prior slices' managers real instances to fan into.
		# Idempotent — a second start() returns false (scene reload after
		# advance_to keeps the session managers across rooms).
		if gs.coop_session != null:
			gs.coop_session.start(dungeon)

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

	# register_room_enemies mints + (in co-op) registers each spawn's
	# enemy_id with session.enemy_sync so the remote-kill receive path
	# (RemoteKillApplier.apply_death) finds the id in the registry and
	# rising-edges true. Before this commit, _setup_current_room called
	# plan_enemy without ever poking enemy_sync — so apply_death returned
	# false for every remote OP_KILL packet (unknown id), the XP fan-out
	# branch was skipped, and AC#3 (kill by any player awards XP to all)
	# failed silently on the receiving client. Solo / null session falls
	# through to a no-registry-touch path: the EnemyData is still minted
	# and returned, so combat in solo behaves identically.
	var spawned := RoomSpawnPlanner.register_room_enemies(_coop_session(), room)
	if spawned.is_empty():
		# No combat in this room — remove the enemy so the HUD counts zero.
		if _enemy != null:
			_enemy.queue_free()
			_enemy = null
	else:
		if _enemy != null:
			_enemy.data = spawned[0]
			_enemy.died.connect(_on_enemy_died)

	_watcher = RoomClearWatcher.new()
	# Pass the local character + session so the watcher fires PRD #52
	# room-clear XP through the right path: solo adds XP to the local
	# character, co-op fans through the party-split broadcaster.
	_watcher.watch(room, _run_controller, _local_character(), _coop_session(), _currency_ledger())

func _coop_session() -> CoopSession:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.coop_session

func _local_character() -> CharacterData:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.current_character

func _currency_ledger() -> CurrencyLedger:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.currency_ledger

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
	# PRD #52 / #61: the boss-cleared edge no longer reloads directly.
	# Call transition() on the controller so the dungeon_transitioned
	# listener can open the stat-allocation screen — the actual reload
	# is deferred until the player presses Continue.
	_run_controller.transition()

# Listens for DungeonRunController.dungeon_transitioned and opens the
# pause menu in dungeon-transition mode (Stats tab + Continue button).
# The Continue button's transition_continued signal then drives the
# actual finalize + reload. PRD #52 / #61.
func _on_dungeon_transitioned() -> void:
	if _hud == null:
		_finalize_and_reload()
		return
	var pm: CanvasLayer = _hud.open_pause_menu_for_transition()
	if pm == null:
		_finalize_and_reload()
		return
	if not pm.transition_continued.is_connected(_on_transition_continued):
		pm.transition_continued.connect(_on_transition_continued, CONNECT_ONE_SHOT)

func _on_transition_continued() -> void:
	_finalize_and_reload()

func _finalize_and_reload() -> void:
	_finalize_completed_run()
	get_tree().reload_current_scene()

# Testable seam for _on_dungeon_completed. The handler itself calls
# reload_current_scene which clobbers the GUT runner's current scene,
# so the testable side effects (meta-bump, controller clear, session
# snapshot) live here. Production path: handler -> seam -> reload. Test
# path: drive seam directly and inspect the side effects.
#
# Session snapshot closes AC#5 ("End-of-run screen shows XP earned by
# each player") on the data side: finalize_run_summary freezes the
# header + rows on the session BEFORE the scene reload would otherwise
# drop them. The future summary screen (HITL) reads
# gs.coop_session.last_run_summary_header / last_run_summary_rows to
# render. Solo / null-session path is silently skipped — no co-op
# means no per-player rows to render.
func _finalize_completed_run() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	DungeonRunCompletion.complete(gs.meta_tracker)
	gs.dungeon_run_controller = null
	if gs.coop_session != null:
		gs.coop_session.finalize_run_summary()
