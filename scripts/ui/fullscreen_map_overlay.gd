class_name FullscreenMapOverlay
extends CanvasLayer

# Modal full-screen minimap (PRD #304 slice 3 / #307). Hosts a large
# MinimapRenderer driven by the SAME Dungeon / DungeonLayout / FloorMapState
# instances as the HUD chip — config_for_chip returns identity-equal refs so
# the two views literally cannot drift in look or behavior.
#
# Open contract:
#   - bind() with the same trio the chip uses, then open()
#   - Solo (no active CoopSession) → pauses the tree so the player can
#     study the map without dying. Co-op → tree keeps running so opening
#     the map can't grief the rest of the party.
# Close affordances:
#   - Tap/click outside the map content rect
#   - Esc (ui_cancel)
#   - Android back button (ui_cancel synthesizes this on Android)
# The overlay_pause_state instance tracks whether THIS overlay's open()
# paused the tree — close() only unpauses if it did. Guards against
# stomping on an unrelated pause (e.g. pause menu opened simultaneously).

# Pure helper — solo runs (no active CoopSession) pause the tree so the
# player can study the map without dying. Null and inactive sessions both
# count as solo because every fall-through path (no autoload / no session
# / pre-handshake) should default to the safer solo-pause behavior.
# Untyped param so tests can pass a fake with .is_active() without
# constructing a fully-started CoopSession + Dungeon. Production call sites
# pass a real CoopSession (or null) — duck-typed `session.is_active()`
# resolves identically against the real class.
# Tracks whether THIS overlay's open() paused the tree, so close() can
# decide whether to unpause without stomping on an unrelated pause that
# was set by another source (pause menu, host pause, dungeon transition,
# etc.). mark_closed clears the flag so a subsequent open's pause
# decision is independent.
class OverlayPauseState:
	extends RefCounted
	var _did_pause: bool = false

	func mark_opened(did_pause: bool) -> void:
		_did_pause = did_pause

	func should_unpause_on_close() -> bool:
		return _did_pause

	func mark_closed() -> void:
		_did_pause = false

# Pure helper — returns a config Dictionary that the overlay's renderer
# binds to. The values are the SAME instances as the chip's, not copies,
# so a mark_revealed write hits both views' floor_state and the overlay
# can never visually drift from the chip (story 20).
static func config_for_chip(d: Dungeon, s: FloorMapState, l: DungeonLayout) -> Dictionary:
	return {"dungeon": d, "floor_state": s, "layout": l}

static func should_pause_world(session) -> bool:
	if session == null:
		return true
	return not session.is_active()

# --- Instance / scene wiring ----------------------------------------------

# Fraction of the viewport each side reserves as a tap-to-close margin. The
# inner rect (60% wide, 70% tall, centered) holds the map; taps outside that
# rect close the overlay. Generous margin keeps the close gesture obvious on
# touch — fingers are not pixel-precise.
const MAP_RECT_FRACTION := Vector2(0.6, 0.7)
const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const MAP_BG_COLOR := Color(0.05, 0.07, 0.12, 0.95)
const MAP_BORDER_COLOR := Color(0.45, 0.55, 0.75, 1.0)
const CLOSE_LABEL_COLOR := Color(0.9, 0.9, 0.95, 0.85)

signal closed

var _renderer: MinimapRenderer = null
var _backdrop: Button = null
var _map_panel: PanelContainer = null
var _close_btn: Button = null
var _dungeon: Dungeon = null
var _state: FloorMapState = null
var _layout: DungeonLayout = null
var _pause_state: OverlayPauseState = OverlayPauseState.new()
# Cached at open() so close() routes through the same session reference
# that decided the pause behavior — avoids a session-flip race (rare, but
# the cost of caching is one ref).
var _opened_session = null

func _ready() -> void:
	# CanvasLayer above HUD (layer = 10). HUD lives at default layer 0;
	# pause menu sits higher still, which is fine — the map overlay should
	# yield to a pause menu opened on top of it.
	layer = 5
	# PROCESS_MODE_ALWAYS so close-via-Esc and tap-outside still respond
	# while the tree is paused in solo (open() flips paused = true).
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_tree()

func _build_tree() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	# Backdrop button — fills the viewport, click anywhere on it closes
	# the overlay. Using a Button (vs ColorRect + _gui_input) is simpler
	# because the map panel above stops the click before it reaches the
	# backdrop, naturally giving us "click outside to close" without
	# manual rect math.
	_backdrop = Button.new()
	_backdrop.flat = true
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	# Tint the backdrop via a child ColorRect — Button doesn't expose a
	# direct background color override that survives the flat=true style.
	var tint := ColorRect.new()
	tint.color = BACKDROP_COLOR
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(tint)
	_backdrop.pressed.connect(_on_backdrop_pressed)
	root.add_child(_backdrop)
	# Map panel — centered, fraction of viewport. PanelContainer with a
	# StyleBoxFlat would be the more idiomatic Godot choice, but a plain
	# Control + ColorRect background keeps the scene-script setup compact
	# and matches the chip's existing styling shape.
	_map_panel = PanelContainer.new()
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = MAP_BG_COLOR
	style.border_color = MAP_BORDER_COLOR
	style.set_border_width_all(2)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	_map_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_map_panel)
	_renderer = MinimapRenderer.new()
	_renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_renderer.custom_minimum_size = Vector2(200, 200)
	_map_panel.add_child(_renderer)
	# Close button + label in the top-right of the map panel. The
	# backdrop already closes on tap-outside, but an explicit visible
	# affordance is required by AC ("clear close affordance") for touch.
	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", CLOSE_LABEL_COLOR)
	_close_btn.add_theme_font_size_override("font_size", 24)
	_close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -36
	_close_btn.offset_top = 4
	_close_btn.offset_right = -8
	_close_btn.offset_bottom = 36
	_close_btn.pressed.connect(close)
	# Parent to the root (not the map panel) so it floats above the
	# renderer without consuming layout space inside the panel.
	root.add_child(_close_btn)
	_layout_map_panel()
	get_viewport().size_changed.connect(_layout_map_panel)

func _layout_map_panel() -> void:
	if _map_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var map_size := Vector2(vp.x * MAP_RECT_FRACTION.x, vp.y * MAP_RECT_FRACTION.y)
	var origin := (vp - map_size) * 0.5
	_map_panel.position = origin
	_map_panel.size = map_size
	if _close_btn != null:
		# Pin the close button to the top-right corner of the map panel.
		var btn_size := Vector2(32, 32)
		_close_btn.position = origin + Vector2(map_size.x - btn_size.x - 4, 4)
		_close_btn.size = btn_size

func bind(d: Dungeon, s: FloorMapState, l: DungeonLayout) -> void:
	_dungeon = d
	_state = s
	_layout = l
	if _renderer != null:
		_renderer.bind(d, s, l)

func set_player_world_pos(p: Vector2) -> void:
	if _renderer != null:
		_renderer.player_world_pos = p

# Slice 5 (#309): the HUD chip polls CoopSession each frame and forwards
# the same snapshot list here so the two views never paint different
# teammate sets.
func set_teammate_snapshots(snaps: Array) -> void:
	if _renderer != null:
		_renderer.teammate_snapshots = snaps

func open() -> void:
	visible = true
	_layout_map_panel()
	# Cache the session decision so close() unpauses with the same context
	# (story 11 — co-op never pauses; story 10 — solo pauses).
	_opened_session = _current_session()
	var should_pause := should_pause_world(_opened_session)
	if should_pause:
		get_tree().paused = true
	_pause_state.mark_opened(should_pause)
	if _renderer != null:
		_renderer.queue_redraw()

func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_state.should_unpause_on_close():
		get_tree().paused = false
	_pause_state.mark_closed()
	closed.emit()

func _current_session():
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.coop_session

func _on_backdrop_pressed() -> void:
	close()

# Esc on desktop and Android back both map to ui_cancel via the project's
# default InputMap. Handle the input here (vs _input) so the action stops
# propagating once we close — the pause menu shouldn't also open from the
# same press.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# Per-frame queue_redraw — matches MinimapHUD.chip's polling cadence so the
# overlay updates the player marker as the player moves (co-op case, where
# the tree is still ticking). In solo the tree is paused but
# process_mode = ALWAYS keeps this firing, which is harmless: the player
# isn't moving, so the redraws are no-op repaints of the same scene.
func _process(_dt: float) -> void:
	if visible and _renderer != null:
		_renderer.queue_redraw()
