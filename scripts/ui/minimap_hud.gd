class_name MinimapHUD
extends Control

# Non-interactive HUD chip that hosts a MinimapRenderer (PRD #304 slice 1).
# Sized + positioned by hud.tscn; this script just instantiates the renderer
# and exposes bind() so the scene-layer orchestrator (main_scene) can hand
# in the dungeon + reveal state + layout once they exist.
#
# Tap-to-open fullscreen lands in #307 — slice 1 stays non-interactive so
# accidental touches in the top-right region don't swallow input intended
# for the pause button next door.

const BG_COLOR := Color(0.05, 0.07, 0.12, 0.7)
const BORDER_COLOR := Color(0.45, 0.55, 0.75, 1.0)

var _renderer: MinimapRenderer = null
var _bg: ColorRect = null

func _ready() -> void:
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

func bind(d: Dungeon, s: FloorMapState, l: DungeonLayout) -> void:
	if _renderer == null:
		return
	_renderer.bind(d, s, l)

# Slice 2 (#306): main_scene pokes the player's world position each frame so
# the marker can move with the player inside the current room, not just snap
# to the room's grid cell. Per-frame queue_redraw below picks it up.
func set_player_world_pos(p: Vector2) -> void:
	if _renderer != null:
		_renderer.player_world_pos = p

# FloorMapState mutates externally (RoomRevealBridge writes from a signal)
# so the renderer needs a kick to repaint. Per-frame queue_redraw is cheap
# — _draw iterates the revealed set (≤ ~10 rooms) and emits rectangles.
# Slice 2 (#306) introduces signal-driven repaint when corridor lines and
# room-type styling make the draw cost worth optimizing.
func _process(_dt: float) -> void:
	if _renderer != null:
		_renderer.queue_redraw()
