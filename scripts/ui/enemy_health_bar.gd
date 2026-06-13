class_name EnemyHealthBar
extends Node2D

# Floating health bar parented above a regular (non-boss) enemy. Polls the
# enemy's data.hp / max_hp each frame and snaps the red Fill ColorRect's
# size.x to bar_width * HUD.hp_bar_ratio(...), mirroring the HUD HP bar's
# instant-snap behavior (no tween). Bosses are intentionally skipped here —
# they get a dedicated HUD-pinned bar in the sibling slice (#248).

const BAR_WIDTH: float = 32.0
const BAR_HEIGHT: float = 4.0
# Enemy sprites are centered on the origin and up to ~48px tall, so the top
# edge sits ~24px above the origin. Clear that plus a small gap so the bar
# floats just above the sprite instead of over its face.
const Y_OFFSET: float = -32.0
const BG_COLOR: Color = Color(0.1, 0.1, 0.1, 0.85)
const FILL_COLOR: Color = Color(0.85, 0.25, 0.25, 1.0)

var _enemy: Node = null
var _bg: ColorRect = null
var _fill: ColorRect = null
var _level_label: Label = null

# Pure-function level-label formatter (PRD #376 / issue #377). Held as a
# static so the format ("Lv N") can be pinned in unit tests without
# instancing the node.
static func format_level(level: int) -> String:
	return "Lv %d" % level

# Pure-function fill width. Multiplied form of HUD.hp_bar_ratio kept here so
# tests can pin the per-bar math (width, ratio, clamps) without instancing a
# node or relying on the player HUD constant.
static func fill_width(hp: int, max_hp: int, bar_width: float) -> float:
	return bar_width * HUD.hp_bar_ratio(hp, max_hp)

# Instantiates and parents a bar to the enemy when it's a regular enemy.
# Boss enemies (data.is_boss == true) get no floating bar — the boss HUD
# bar in #248 owns that presentation. Safe to call when data is null
# (treated as non-boss); the bar's _process bails if data goes missing.
static func attach(enemy: Enemy) -> EnemyHealthBar:
	if enemy == null:
		return null
	if enemy.data != null and enemy.data.is_boss:
		return null
	var bar := EnemyHealthBar.new()
	bar._enemy = enemy
	enemy.add_child(bar)
	return bar

func _ready() -> void:
	position = Vector2(-BAR_WIDTH * 0.5, Y_OFFSET)
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_fill = ColorRect.new()
	_fill.color = FILL_COLOR
	_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	# "Lv N" label centered above the bar. Positioned via its own size on
	# resize so the text sits just above the bg without overlapping.
	_level_label = Label.new()
	_level_label.text = format_level(1)
	_level_label.add_theme_font_size_override("font_size", 8)
	_level_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_level_label.add_theme_constant_override("outline_size", 2)
	_level_label.size = Vector2(BAR_WIDTH, 10)
	_level_label.position = Vector2(0, -10)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_label)

func _process(_dt: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var data = _enemy.get("data")
	if data == null:
		return
	if _fill != null:
		_fill.size.x = fill_width(data.hp, data.max_hp, BAR_WIDTH)
	if _level_label != null:
		_level_label.text = format_level(int(data.level))
