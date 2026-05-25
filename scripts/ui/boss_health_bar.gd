class_name BossHealthBar
extends Control

# Dedicated boss HP bar pinned to the top-center of the HUD CanvasLayer.
# Polls the "enemies" group each frame for the live boss (data.is_boss);
# shows the bar + name + cur/max numbers while a boss exists, hides
# otherwise. Mirrors HUD.hp_bar_ratio fill math used by the player HUD
# and EnemyHealthBar so all three bars share one clamped, divide-by-
# zero-safe implementation. Floating per-enemy bars (#247) skip bosses
# so this bar owns the boss presentation without double-render.

const BAR_WIDTH: float = 240.0
const BAR_HEIGHT: float = 14.0
const TOP_MARGIN: float = 8.0
const LABEL_HEIGHT: float = 14.0
const BG_COLOR: Color = Color(0.1, 0.05, 0.07, 0.85)
const FILL_COLOR: Color = Color(0.85, 0.25, 0.25, 1.0)
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const LABEL_FONT_SIZE: int = 12

var _bg: ColorRect = null
var _fill: ColorRect = null
var _label: Label = null
var _hud: CanvasLayer = null

# Pure label render for the boss bar: "Name  cur/max". Double-space
# separator picks out the name from the numbers without a heavier
# delimiter and reads as one phrase at HUD font size. Empty name is
# allowed — defensive against an unconfigured EnemyData; surfaces as a
# leading "  cur/max" rather than crashing the HUD poll.
static func format_boss_hp(boss_name: String, hp: int, max_hp: int) -> String:
	return "%s  %d/%d" % [boss_name, hp, max_hp]

# Room gate: the boss bar only shows once the player is physically inside the
# boss room. The boss enemy spawns at dungeon load, so existence alone isn't
# enough — we test the player's world position against the boss's room_bounds
# (world-space Rect2 set by RoomSpawnPlanner). Empty/arealess bounds means we
# can't tell where the room is, so stay hidden rather than show prematurely.
static func should_show(room_bounds: Rect2, player_pos: Vector2) -> bool:
	if not room_bounds.has_area():
		return false
	return room_bounds.has_point(player_pos)

# Instantiates the bar under the HUD CanvasLayer. The HUD's _ready calls
# this exactly once; subsequent polls reuse the same node and toggle
# visibility based on whether a boss is currently alive.
static func attach(hud: CanvasLayer) -> BossHealthBar:
	if hud == null:
		return null
	var bar := BossHealthBar.new()
	bar._hud = hud
	hud.add_child(bar)
	return bar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -BAR_WIDTH * 0.5
	offset_right = BAR_WIDTH * 0.5
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + BAR_HEIGHT + LABEL_HEIGHT
	_label = Label.new()
	_label.add_theme_color_override("font_color", LABEL_COLOR)
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(BAR_WIDTH, LABEL_HEIGHT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.position = Vector2(0.0, LABEL_HEIGHT)
	_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_fill = ColorRect.new()
	_fill.color = FILL_COLOR
	_fill.position = Vector2(0.0, LABEL_HEIGHT)
	_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	visible = false

func _process(_dt: float) -> void:
	var boss := _find_boss()
	if boss == null:
		visible = false
		return
	var data = boss.get("data")
	if data == null:
		visible = false
		return
	var player := _find_player()
	if player == null or not should_show(data.room_bounds, player.global_position):
		visible = false
		return
	visible = true
	if _fill != null:
		_fill.size.x = BAR_WIDTH * HUD.hp_bar_ratio(data.hp, data.max_hp)
	if _label != null:
		_label.text = format_boss_hp(data.enemy_name, data.hp, data.max_hp)

func _find_boss() -> Node:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		var d = n.get("data")
		if d != null and d.is_boss and d.hp > 0:
			return n
	return null

func _find_player() -> Node2D:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D:
			return n
	return null
