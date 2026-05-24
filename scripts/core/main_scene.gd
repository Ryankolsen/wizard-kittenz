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
const EXIT_DOOR_SCENE_PATH := "res://scenes/exit_door.tscn"
const POWER_UP_SCENE_PATH := "res://scenes/power_up.tscn"
const CONGRATS_SCENE_PATH := "res://scenes/congratulations_screen.tscn"
const BAR_ROOM_SCENE_PATH := "res://scenes/bar_room.tscn"
const BossDeathEffectScript := preload("res://scripts/vfx/boss_death_effect.gd")

var _run_controller: DungeonRunController = null
var _watchers: Array[RoomClearWatcher] = []
var _hud: HUD = null
var _dungeon_layout: DungeonLayout = null
var _spawn_planner: RoomSpawnPlanner = null
var _exit_door: ExitDoor = null
var _congrats_screen: CongratulationsScreen = null

# PRD #132 / issue #134 — per-floor stat tracking for the congratulations
# screen. Enemies-slain is incremented in _on_enemy_died. XP and gold
# snapshots are taken at dungeon start so _build_floor_summary can compute
# the delta at completion. All three reset whenever a new dungeon starts.
var _enemies_slain_this_floor: int = 0
var _xp_at_floor_start: int = 0
var _gold_at_floor_start: int = 0
var _boss_death_position: Vector2 = Vector2.ZERO

# Bar-room transition state. Stored as members (rather than locals) so the
# entrance-tile detector in _process and the round-trip tests can read them.
# _tilemap_painter is also kept around so the bar_entrance_tiles produced by
# the last paint() call drive the entrance trigger directly (no need to
# recompute the layout or re-scan the TileMap).
var _tilemap: TileMap = null
var _player: Node2D = null
var _tilemap_painter: DungeonTilemapPainter = null
var _bar_room_scene: Node = null
var _player_dungeon_position: Vector2 = Vector2.ZERO
# After the player exits the bar they're restored to the entrance tile in the
# dungeon — which would immediately retrigger _enter_bar_room on the next
# process frame. This flag suppresses re-entry until the player moves off the
# entrance footprint, then re-arms.
var _suppress_bar_entry: bool = false
# Dungeon nodes whose process_mode we flipped to DISABLED on bar entry, so
# enemies / pickups / the exit door don't keep ticking while the player is
# inside the bar. Restored to PROCESS_MODE_INHERIT on bar exit. Their
# visibility is also flipped off (and back on at exit) so the bar's small
# tile footprint isn't seen sitting on top of the dungeon's tiles + props.
var _paused_dungeon_nodes: Array = []
var _hidden_dungeon_nodes: Array = []
# TileMap layers we disabled on bar entry. set_layer_enabled(false) drops
# both rendering and physics collisions for those tiles, so the dungeon's
# wall colliders don't trap the player inside the bar's footprint.
var _disabled_tilemap_layers: Array[int] = []

func _ready() -> void:
	_hud = $HUD
	_tilemap = $TileMap
	_player = $Player

	var gs := get_node_or_null("/root/GameState")

	if gs == null or gs.dungeon_run_controller == null:
		_start_new_dungeon(gs)
	else:
		_run_controller = gs.dungeon_run_controller

	_paint_dungeon()

	# Issue #98: dungeon completion is now defined by walking through the
	# ExitDoor, not by killing the boss. The boss-clear edge only opens the
	# door (via boss_room_cleared -> _exit_door.open); the player's actual
	# walk-through fires _on_dungeon_completed and drives the transition.
	_run_controller.boss_room_cleared.connect(_on_boss_room_cleared)
	_run_controller.dungeon_transitioned.connect(_on_dungeon_transitioned)
	# Issue #99: rising-edge dedup for dungeon transitions. The exit-door
	# walk-through now requests the transition through the controller's
	# idempotent gate; this handler fans the request out to either the
	# solo path (drive transition() locally) or the co-op path (host mints
	# + broadcasts a new seed; peer sends a request packet to the host).
	_run_controller.dungeon_transition_requested.connect(_on_dungeon_transition_requested)

	_connect_lobby_signals()

	_setup_rooms()
	_spawn_exit_door()

# Co-op wire bridge — subscribes main_scene to the lobby's #99 signals so a
# remote boss-clear opens the local exit door, a host mint broadcasts the
# new dungeon seed to all clients, and the host receives peer transition
# requests. is_connected guards make the subscriptions idempotent across
# scene reloads (the lobby instance survives reload via GameState).
func _connect_lobby_signals() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.lobby == null:
		return
	var lobby: NakamaLobby = gs.lobby
	if not lobby.boss_cleared_received.is_connected(_on_boss_cleared_received):
		lobby.boss_cleared_received.connect(_on_boss_cleared_received)
	if not lobby.transition_requested_received.is_connected(_on_transition_requested_received):
		lobby.transition_requested_received.connect(_on_transition_requested_received)
	if not lobby.dungeon_transition_received.is_connected(_on_dungeon_transition_received):
		lobby.dungeon_transition_received.connect(_on_dungeon_transition_received)

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
	_tilemap_painter = DungeonTilemapPainter.new()
	_tilemap_painter.paint(_dungeon_layout, tilemap, _run_controller.dungeon)
	var player := get_node_or_null("Player")
	if player != null:
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			DungeonTilemapPainter.apply_camera_limits(camera, tilemap)

func _start_new_dungeon(gs) -> void:
	var seed := _dungeon_seed_for(gs)
	var dungeon := DungeonGenerator.generate(seed)
	# Stamp depth so depth-gated content (ChestSpawner rare-unlock — #220)
	# can branch off it. dungeons_completed is the count BEFORE this run
	# finalizes, which makes it equivalent to "depth = floor number - 1".
	if gs != null and gs.meta_tracker != null:
		dungeon.depth = gs.meta_tracker.dungeons_completed
	_run_controller = DungeonRunController.new()
	_run_controller.start(dungeon)
	_run_controller.seed = seed
	_enemies_slain_this_floor = 0
	_xp_at_floor_start = _snapshot_xp(gs)
	_gold_at_floor_start = _snapshot_gold(gs)
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
			gs.coop_session.start(dungeon, _local_skill_tree(), gs.lobby)

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
	var power_up_scene := load(POWER_UP_SCENE_PATH)
	for room in _run_controller.dungeon.rooms:
		var data: EnemyData = _spawn_planner.enemy_data_for_room(room.id)
		if data != null and not _run_controller.is_room_cleared(room.id):
			var enemy: Enemy = enemy_scene.instantiate()
			enemy.data = data
			enemy.position = data.spawn_position
			enemy.died.connect(_on_enemy_died.bind(enemy))
			add_child(enemy)
		var pu_type := RoomSpawnPlanner.plan_powerup(room)
		if pu_type != "" and _dungeon_layout != null and not _run_controller.cleared_ids().has(room.id):
			var pickup: PowerUpPickup = power_up_scene.instantiate()
			pickup.power_up_type = pu_type
			pickup.position = _dungeon_layout.room_center_world(room.id)
			add_child(pickup)
		var watcher := RoomClearWatcher.new()
		# Pass the local character + session so the watcher fires PRD #52
		# room-clear XP through the right path: solo adds XP to the local
		# character, co-op fans through the party-split broadcaster.
		watcher.watch(room, _run_controller, _local_character(), _coop_session(), _currency_ledger(), _local_skill_tree())
		_watchers.append(watcher)
	_spawn_healing_box()
	_spawn_chest()

# Per-frame check that moves the player into the bar room scene when they
# step onto a bar-entrance tile (issue #187). Tile-based detection rather
# than an Area2D body_entered trigger so the test path
# (set _player.global_position, await one process frame) is deterministic
# without needing the physics step to fire.
func _process(_delta: float) -> void:
	_check_bar_entrance()


func _check_bar_entrance() -> void:
	if _bar_room_scene != null:
		return
	if _player == null or _tilemap == null or _tilemap_painter == null:
		return
	if _tilemap_painter.bar_entrance_tiles.is_empty():
		return
	var local: Vector2 = _tilemap.to_local(_player.global_position)
	var cell: Vector2i = _tilemap.local_to_map(local)
	var on_entrance: bool = cell in _tilemap_painter.bar_entrance_tiles
	if _suppress_bar_entry:
		if not on_entrance:
			_suppress_bar_entry = false
		return
	if on_entrance:
		_enter_bar_room()


# Mounts bar_room.tscn as a child of main_scene at the player's current
# dungeon position, pauses + hides the dungeon's tilemap / enemies / pickups
# / exit door, and lets the player stand still inside the bar's footprint.
# The dungeon scene stays in the tree (just paused + hidden) so HP / MP /
# currency / killed-enemy state are preserved by the round trip — none of
# the long-lived state lives on a node we touch here.
#
# Mounting at the player's position (instead of the old
# BAR_OVERLAY_OFFSET = (-50000, -50000) hack) keeps the bar's coordinates
# inside the dungeon's camera-limit rect, so the player camera follows
# normally with no need to lift its clamps. The dungeon visuals + collisions
# are hidden underneath while the bar is up.
func _enter_bar_room() -> void:
	if _bar_room_scene != null:
		return
	var scene: PackedScene = load(BAR_ROOM_SCENE_PATH)
	if scene == null:
		return
	_player_dungeon_position = _player.global_position
	_pause_dungeon_entities()
	var bar: Node2D = scene.instantiate() as Node2D
	bar.name = "BarRoomScene"
	if bar.has_signal("player_exited_bar"):
		bar.player_exited_bar.connect(_on_player_exited_bar)
	add_child(bar)
	# Push the bar to the front of the child list so the Player (and any later
	# siblings like HUD) draw on top of the bar's tilemap and props. Without
	# this, add_child appends BarRoomScene after Player and its subtree
	# overlaps the player sprite in scene-tree draw order.
	move_child(bar, 0)
	bar.global_position = _player.global_position
	_bar_room_scene = bar


# Disables processing AND rendering on every dungeon entity that ticks or
# draws — enemies, pickups, the exit door, plus the dungeon TileMap itself.
# The player and HUD stay running and visible: the player walks inside the
# bar, the HUD still renders. Hiding the TileMap (vs. just pausing it) keeps
# the dungeon's wall colliders from blocking movement inside the bar — a
# hidden CanvasItem with no _process tick effectively drops both visuals and
# tile collision shapes for the duration of the visit.
func _pause_dungeon_entities() -> void:
	_paused_dungeon_nodes.clear()
	_hidden_dungeon_nodes.clear()
	_disabled_tilemap_layers.clear()
	for child in get_children():
		if child == _player or child == _hud:
			continue
		if child is BarRoom:
			continue
		if child.process_mode != Node.PROCESS_MODE_DISABLED:
			_paused_dungeon_nodes.append(child)
			child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is CanvasItem and (child as CanvasItem).visible:
			_hidden_dungeon_nodes.append(child)
			(child as CanvasItem).visible = false
	# TileMap collisions are static — process_mode + visible don't drop them.
	# Walk each layer and disable it so the dungeon's wall colliders can't
	# trap the player while they're inside the bar.
	if _tilemap != null:
		for layer in range(_tilemap.get_layers_count()):
			if _tilemap.is_layer_enabled(layer):
				_disabled_tilemap_layers.append(layer)
				_tilemap.set_layer_enabled(layer, false)


# Tears down bar_room.tscn, restores the player to the entrance tile in the
# dungeon, and re-enables every dungeon node that was paused + hidden on
# entry. The _suppress_bar_entry flag stops _check_bar_entrance from
# immediately re-firing on the restored position; it re-arms once the
# player walks off the entrance footprint.
func _on_player_exited_bar() -> void:
	if _bar_room_scene != null:
		_bar_room_scene.queue_free()
		_bar_room_scene = null
	if _player != null:
		_player.global_position = _player_dungeon_position
	_suppress_bar_entry = true
	for n in _paused_dungeon_nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT
	_paused_dungeon_nodes.clear()
	for n in _hidden_dungeon_nodes:
		if is_instance_valid(n) and n is CanvasItem:
			(n as CanvasItem).visible = true
	_hidden_dungeon_nodes.clear()
	if _tilemap != null:
		for layer in _disabled_tilemap_layers:
			_tilemap.set_layer_enabled(layer, true)
	_disabled_tilemap_layers.clear()


func _spawn_healing_box() -> void:
	if _run_controller == null or _run_controller.dungeon == null or _dungeon_layout == null:
		return
	var start_id := _run_controller.dungeon.start_id
	var box := HealingBox.new()
	box.position = _dungeon_layout.room_center_world(start_id)
	add_child(box)


# Slice 2 of PRD #217 / issue #219: ChestSpawner returns up to TARGET_COUNT
# placements scattered across non-start rooms; we instantiate one ChestEntity
# per placement and add it to world at (room_center + offset). The RNG is
# seeded from the dungeon's seed so a re-roll of the same dungeon places
# chests identically — see test_chest_spawner.gd determinism tests.
func _spawn_chest() -> void:
	if _run_controller == null or _run_controller.dungeon == null or _dungeon_layout == null:
		return
	var scene: PackedScene = load("res://scenes/chest.tscn")
	if scene == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _chest_spawn_seed()
	var placements := ChestSpawner.plan(_run_controller.dungeon, rng)
	var ledger := _currency_ledger()
	var session := _coop_session()
	for placement in placements:
		var chest_entity: ChestEntity = scene.instantiate() as ChestEntity
		if chest_entity == null:
			continue
		chest_entity.chest = placement["chest"]
		chest_entity.ledger = ledger
		chest_entity.chest_id = placement["chest_id"]
		# Wiring `session` flips ChestEntity into co-op mode: the chest stays
		# CLOSED until every present player has opened it (slice 4 / #221).
		# Solo / pre-handshake leaves session null and the chest fades on
		# the first open (matches #218 behavior).
		chest_entity.session = session
		var room_id: int = placement["room_id"]
		var offset: Vector2 = placement["position"]
		chest_entity.position = _dungeon_layout.room_center_world(room_id) + offset
		add_child(chest_entity)

# Stable seed for the chest spawner's RNG. Co-op clients converge on the
# agreed dungeon seed via DungeonSeedSync so both ends place chests
# identically; solo / pre-handshake derives a deterministic seed from the
# dungeon's room sequence so re-entering the same run gives the same layout.
func _chest_spawn_seed() -> int:
	var gs := get_node_or_null("/root/GameState")
	var agreed := _dungeon_seed_for(gs)
	if agreed != -1:
		return agreed
	return hash(_run_controller.dungeon.room_type_sequence())

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

func _local_skill_tree() -> SkillTree:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.skill_tree

func _on_enemy_died(enemy: Enemy) -> void:
	if enemy == null or enemy.data == null:
		return
	_enemies_slain_this_floor += 1
	if enemy.data.is_boss:
		_boss_death_position = enemy.global_position
	# Fan the death across all watchers; each watcher gates on its own
	# expected enemy_id set, so only the matching room's watcher
	# rising-edges true. Cheaper than maintaining a parallel
	# room_id -> watcher map for the small per-dungeon room count.
	for watcher in _watchers:
		watcher.notify_death(enemy.data.enemy_id)

# PRD #132 / issue #134 — assembles the FloorRunSummary handed to the
# congratulations screen. Floor number is dungeons_completed + 1 because
# this fires BEFORE DungeonRunCompletion.complete() increments the
# counter; the floor the player just cleared is the (current + 1)th.
# XP / gold are deltas from the start-of-floor snapshots so any meta
# carry-over already present at dungeon start is excluded.
func _build_floor_summary() -> FloorRunSummary:
	var gs := get_node_or_null("/root/GameState")
	var floor_number := 1
	if gs != null and gs.meta_tracker != null:
		floor_number = gs.meta_tracker.dungeons_completed + 1
	var xp_earned: int = _snapshot_xp(gs) - _xp_at_floor_start
	var gold_earned: int = _snapshot_gold(gs) - _gold_at_floor_start
	return FloorRunSummary.new(
		floor_number, _enemies_slain_this_floor, xp_earned, gold_earned)

func _snapshot_xp(gs) -> int:
	if gs == null or gs.current_character == null:
		return 0
	return int(gs.current_character.xp)

func _snapshot_gold(gs) -> int:
	if gs == null or gs.currency_ledger == null:
		return 0
	return int(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD))

# Spawns the ExitDoor scene at the boss room's world center. The door starts
# locked; boss_room_cleared (wired in _ready) drives the transition to open.
# Already-cleared boss rooms (resumed run) open the door immediately so the
# player isn't blocked from a run they've effectively finished.
func _spawn_exit_door() -> void:
	if _run_controller == null or _run_controller.dungeon == null:
		return
	if _dungeon_layout == null:
		return
	var boss_id: int = _run_controller.dungeon.boss_id
	if boss_id < 0:
		return
	var scene := load(EXIT_DOOR_SCENE_PATH)
	if scene == null:
		return
	_exit_door = scene.instantiate()
	var entrance: Dictionary = _dungeon_layout.boss_exit_position(boss_id)
	_exit_door.position = entrance["position"]
	_exit_door.rotation = entrance["rotation"]
	_exit_door.player_exited_dungeon.connect(_on_player_exited_dungeon)
	add_child(_exit_door)
	if _run_controller.is_room_cleared(boss_id):
		_exit_door.open()

func _on_boss_room_cleared() -> void:
	if _exit_door != null:
		_exit_door.open()
	var effect := BossDeathEffectScript.new()
	effect.global_position = _boss_death_position
	add_child(effect)
	# Issue #99 AC1: in co-op, the host fans the boss-clear edge to every
	# peer so all clients open their door simultaneously. Non-host clients
	# silently no-op via lobby.send_boss_cleared_async's is_local_host
	# gate — only the host should ever observe boss_room_cleared first
	# (host-authoritative enemy_sync), but the gate keeps the contract
	# explicit.
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.lobby != null:
		gs.lobby.send_boss_cleared_async()

# Inbound co-op boss-clear: a peer opens its local exit door when the host's
# OP_BOSS_CLEARED packet arrives. ExitDoor.open is idempotent so the host's
# self-echo (it also calls open() locally via _on_boss_room_cleared) is
# harmless.
func _on_boss_cleared_received() -> void:
	if _exit_door != null:
		_exit_door.open()

# Player walked through the now-open exit door. Routes through the
# controller's idempotent dungeon_transition_requested gate so duplicate
# walk-throughs (in co-op, two players hitting the door at once) collapse
# to a single transition. Solo path also passes through this gate — first
# call wins, signal handler drives transition().
func _on_player_exited_dungeon() -> void:
	_run_controller.request_dungeon_transition()

# Fans the gated transition request to the right side. Solo / no-co-op:
# drive transition() directly (existing pause-menu / reload chain). Co-op
# host: reset + mint a new dungeon seed, broadcast OP_DUNGEON_TRANSITION_START
# to every client (the host's self-echo loops back through
# _on_dungeon_transition_received which is what actually drives the local
# reload). Co-op peer: send OP_REQUEST_TRANSITION to ask the host to mint.
func _on_dungeon_transition_requested() -> void:
	var gs := get_node_or_null("/root/GameState")
	var lobby: NakamaLobby = gs.lobby if gs != null else null
	if lobby == null or lobby.lobby_state == null:
		_on_dungeon_completed()
		return
	if lobby.is_local_host():
		var seed_sync: DungeonSeedSync = _seed_sync_for(gs)
		if seed_sync == null:
			_on_dungeon_completed()
			return
		if seed_sync.is_agreed():
			seed_sync.reset()
		var next_seed := seed_sync.host_mint()
		lobby.send_dungeon_transition_async(next_seed)
	else:
		lobby.send_request_transition_async()

# Inbound co-op host request from a peer who walked through the exit. Only
# routed to the host by NakamaLobby._route_request_transition. The host
# pipes the request through its own controller gate, which collapses
# duplicates (two peers walking through together → one mint).
func _on_transition_requested_received() -> void:
	if _run_controller != null:
		_run_controller.request_dungeon_transition()

# Inbound new-dungeon seed from the host. Applies the seed to the lobby's
# DungeonSeedSync (idempotent — the host's own self-echo is a no-op since
# the host already minted) and drives the local transition() chain to
# reload into the new dungeon.
func _on_dungeon_transition_received(seed: int) -> void:
	var gs := get_node_or_null("/root/GameState")
	var seed_sync: DungeonSeedSync = _seed_sync_for(gs)
	if seed_sync != null:
		if seed_sync.is_agreed() and seed_sync.current_seed() != seed:
			seed_sync.reset()
		if not seed_sync.is_agreed():
			seed_sync.apply_remote_seed(seed)
	_on_dungeon_completed()

func _seed_sync_for(gs) -> DungeonSeedSync:
	if gs == null or gs.coop_session == null:
		return null
	return gs.coop_session.dungeon_seed_sync

func _on_dungeon_completed() -> void:
	# PRD #52 / #61: the boss-cleared edge no longer reloads directly.
	# Call transition() on the controller so the dungeon_transitioned
	# listener can open the stat-allocation screen — the actual reload
	# is deferred until the player presses Continue.
	_run_controller.transition()

# Listens for DungeonRunController.dungeon_transitioned and shows the
# CongratulationsScreen overlay (PRD #132 / issue #135). The screen
# displays the per-floor summary + headline; its three buttons emit
# typed signals that drive: Next Floor → finalize + reload (this slice);
# Update Character → #136; Save & Exit → #137 (placeholder prints here).
func _on_dungeon_transitioned() -> void:
	var scene := load(CONGRATS_SCENE_PATH)
	if scene == null:
		_finalize_and_reload()
		return
	_congrats_screen = scene.instantiate()
	var summary := _build_floor_summary()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var is_first_boss := _is_first_boss_clear()
	var message := CongratulationsMessageBuilder.build(is_first_boss, rng)
	add_child(_congrats_screen)
	_congrats_screen.populate(summary, message)
	_congrats_screen.next_floor_pressed.connect(_on_congrats_next_floor_pressed)
	_congrats_screen.update_character_pressed.connect(_on_congrats_update_character_pressed)
	_congrats_screen.save_and_exit_pressed.connect(_on_congrats_save_and_exit_pressed)

# True when the player has never completed a dungeon before. Drives the
# special first-boss headline path in CongratulationsMessageBuilder.
# Reads dungeons_completed BEFORE _finalize_completed_run increments it,
# matching the floor-number convention in _build_floor_summary.
func _is_first_boss_clear() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.meta_tracker == null:
		return true
	return gs.meta_tracker.dungeons_completed == 0

func _on_congrats_next_floor_pressed() -> void:
	_finalize_and_reload()

# PRD #132 / issue #136 — opens the existing pause-menu stat-allocation
# screen in transition mode on top of the congratulations overlay. The
# pause menu's Continue press fires transition_continued, which drives
# the same finalize + reload path Next Floor takes. CONNECT_ONE_SHOT so
# a second open (impossible today but cheap insurance) can't stack
# duplicate handlers.
func _on_congrats_update_character_pressed() -> void:
	if _congrats_screen != null:
		_congrats_screen.hide()
	if _hud == null:
		_finalize_and_reload()
		return
	var pm := _hud.open_pause_menu_for_transition()
	if pm == null:
		_finalize_and_reload()
		return
	if not pm.transition_continued.is_connected(_on_transition_continued):
		pm.transition_continued.connect(_on_transition_continued, CONNECT_ONE_SHOT)

func _on_transition_continued() -> void:
	_finalize_and_reload()

# PRD #132 / issue #137 — persists the cleared-floor progress, drops
# the in-flight dungeon run so the next boot starts fresh, and returns
# the player to the character-creation / main-menu scene. Distinct from
# Next Floor (no _finalize_and_reload): Save & Exit exits the dungeon
# entirely. SaveManager.save_from_state reads every persisted field off
# GameState directly, matching the pause-menu Quit Dungeon path.
func _on_congrats_save_and_exit_pressed() -> void:
	SaveManager.save_from_state()
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.dungeon_run_controller = null
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")

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
