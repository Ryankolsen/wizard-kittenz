extends Node2D

# Scene-layer orchestrator for the main dungeon room. Bridges the pure-data
# layer (DungeonRunController + RoomClearWatcher) to the scene tree:
#   - Initializes or resumes the dungeon run from GameState (survives reloads).
#   - Spawns every combat room's Enemy node at its layout-derived world center
#     at dungeon load (issue #96). Replaces the lazy per-room-enter pattern.
#   - Creates a RoomClearWatcher per combat room up-front so kills in any room
#     fire mark_room_cleared without a scene reload.
#   - Wires each Enemy.died -> the matching watcher's notify_death.
#   - Handles dungeon_completed (boss killed): calls DungeonRunCompletion,
#     clears run state, and reloads for a new dungeon.
#
# No-enemy rooms (start, power-up): no Enemy is instantiated; their watchers
# auto-clear immediately on construction.

const ENEMY_SCENE_PATH := "res://scenes/enemy.tscn"

var _run_controller: DungeonRunController = null
var _watchers: Array[RoomClearWatcher] = []
var _hud: HUD = null
var _dungeon_layout: DungeonLayout = null
var _spawn_planner: RoomSpawnPlanner = null

func _ready() -> void:
	_hud = $HUD

	var gs := get_node_or_null("/root/GameState")

	if gs == null or gs.dungeon_run_controller == null:
		_start_new_dungeon(gs)
	else:
		_run_controller = gs.dungeon_run_controller

	_paint_dungeon()

	_run_controller.dungeon_completed.connect(_on_dungeon_completed)
	_run_controller.dungeon_transitioned.connect(_on_dungeon_transitioned)

	_setup_rooms()

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

# Spawns every combat room's Enemy node and creates a watcher per room at
# dungeon load (issue #96). Replaces the lazy per-room-enter pattern: all
# enemies exist simultaneously in the scene tree and each watcher tracks its
# room's kills independently. Start / power-up rooms get a watcher that
# auto-clears immediately (no enemy instantiated).
#
# Already-cleared rooms (from a resumed run via the save/restore path)
# skip enemy instantiation so the player doesn't re-fight a room they've
# already finished. The watcher is still created so room_cleared refires
# on auto-clear and the controller's _cleared flag is consistent.
func _setup_rooms() -> void:
	if _run_controller == null or _run_controller.dungeon == null:
		return

	_spawn_planner = RoomSpawnPlanner.new()
	_spawn_planner.register_all_room_enemies(
		_run_controller.dungeon, _dungeon_layout, _coop_session())

	var enemy_scene := load(ENEMY_SCENE_PATH)
	for room in _run_controller.dungeon.rooms:
		var data: EnemyData = _spawn_planner.enemy_data_for_room(room.id)
		if data != null and not _run_controller.is_room_cleared(room.id):
			var enemy: Enemy = enemy_scene.instantiate()
			enemy.data = data
			enemy.position = data.spawn_position
			enemy.died.connect(_on_enemy_died.bind(enemy))
			add_child(enemy)
		var watcher := RoomClearWatcher.new()
		# Pass the local character + session so the watcher fires PRD #52
		# room-clear XP through the right path: solo adds XP to the local
		# character, co-op fans through the party-split broadcaster.
		watcher.watch(room, _run_controller, _local_character(), _coop_session(), _currency_ledger())
		_watchers.append(watcher)

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

func _on_enemy_died(enemy: Enemy) -> void:
	if enemy == null or enemy.data == null:
		return
	# Fan the death across all watchers; each watcher gates on its own
	# expected enemy_id set, so only the matching room's watcher
	# rising-edges true. Cheaper than maintaining a parallel
	# room_id -> watcher map for the small per-dungeon room count.
	for watcher in _watchers:
		watcher.notify_death(enemy.data.enemy_id)

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
