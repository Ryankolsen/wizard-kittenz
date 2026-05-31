class_name MinimapHUD
extends Control

# Tappable HUD chip that hosts a MinimapRenderer (PRD #304). Slice 1
# rendered the chip but kept it non-interactive; slice 3 (#307) makes it
# a tap/click target that lazily instantiates a _FullscreenMapOverlay and
# binds it to the same Dungeon / FloorMapState / DungeonLayout instances —
# config_for_chip enforces identity-equal refs so the two views never drift.
#
# The chip itself stays a simple Control; the overlay is a CanvasLayer
# parented under the chip on first open. Lazy-instantiation matches the
# pause_menu pattern in hud.gd so an unused overlay never enters the tree.

const BG_COLOR := Color(0.05, 0.07, 0.12, 0.7)
const BORDER_COLOR := Color(0.45, 0.55, 0.75, 1.0)

# Preload sidesteps the class_name registry — sibling class_name resolution
# is load-order-fragile in Godot 4.x (see the analogous note in
# coop_session.gd). Reaching the script + scene via const preload guarantees
# the type and static methods resolve here regardless of which file the
# engine parses first.
const _FullscreenMapOverlay = preload("res://scripts/ui/fullscreen_map_overlay.gd")
const _FullscreenMapOverlayScene := preload("res://scenes/fullscreen_map_overlay.tscn")

var _renderer: MinimapRenderer = null
var _bg: ColorRect = null
var _tap_btn: Button = null
var _dungeon: Dungeon = null
var _state: FloorMapState = null
var _layout: DungeonLayout = null
var _player_world_pos: Vector2 = Vector2.ZERO
var _overlay: _FullscreenMapOverlay = null

func _ready() -> void:
	# The chip itself ignores mouse — the tap surface is a dedicated child
	# Button below, so the chip's mouse_filter doesn't fight with sibling
	# HUD widgets in the top-right region.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_renderer = MinimapRenderer.new()
	_renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_renderer)
	# Invisible Button covering the whole chip — Button gives us
	# tap/click parity on desktop + touch without any platform branching.
	# Flat + transparent so it doesn't paint over the renderer.
	_tap_btn = Button.new()
	_tap_btn.flat = true
	_tap_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_btn.focus_mode = Control.FOCUS_NONE
	_tap_btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_tap_btn.pressed.connect(_on_chip_pressed)
	add_child(_tap_btn)

func bind(d: Dungeon, s: FloorMapState, l: DungeonLayout) -> void:
	_dungeon = d
	_state = s
	_layout = l
	if _renderer != null:
		_renderer.bind(d, s, l)
	if _overlay != null:
		# Rebind a live overlay so a mid-run dungeon swap (floor advance)
		# doesn't leave the overlay pointing at the previous floor.
		var cfg := _FullscreenMapOverlay.config_for_chip(d, s, l)
		_overlay.bind(cfg["dungeon"], cfg["floor_state"], cfg["layout"])

# Slice 2 (#306): main_scene pokes the player's world position each frame so
# the marker can move with the player inside the current room, not just snap
# to the room's grid cell. Per-frame queue_redraw below picks it up.
func set_player_world_pos(p: Vector2) -> void:
	_player_world_pos = p
	if _renderer != null:
		_renderer.player_world_pos = p
	if _overlay != null:
		_overlay.set_player_world_pos(p)

# FloorMapState mutates externally (RoomRevealBridge writes from a signal)
# so the renderer needs a kick to repaint. Per-frame queue_redraw is cheap
# — _draw iterates the revealed set (≤ ~10 rooms) and emits rectangles.
# Signal-driven repaint is a slice 4+ concern when draw cost makes the
# poll worth replacing.
func _process(_dt: float) -> void:
	if _renderer != null:
		_renderer.queue_redraw()

func _on_chip_pressed() -> void:
	if _dungeon == null or _state == null or _layout == null:
		return
	var overlay := _ensure_overlay()
	var cfg := _FullscreenMapOverlay.config_for_chip(_dungeon, _state, _layout)
	overlay.bind(cfg["dungeon"], cfg["floor_state"], cfg["layout"])
	overlay.set_player_world_pos(_player_world_pos)
	overlay.open()

func _ensure_overlay() -> _FullscreenMapOverlay:
	if _overlay == null:
		_overlay = _FullscreenMapOverlayScene.instantiate()
		add_child(_overlay)
	return _overlay
