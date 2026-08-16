class_name HoomanHealthBar
extends Node2D

# Floating health bar parented above the rented Hooman companion (issue
# #497). Mirrors EnemyHealthBar's structure and reuses its fill-ratio math
# via HUD.hp_bar_ratio; no level label since the hooman has no level.

const BAR_WIDTH: float = 32.0
const BAR_HEIGHT: float = 4.0
const Y_OFFSET: float = -32.0
const BG_COLOR: Color = Color(0.1, 0.1, 0.1, 0.85)
const FILL_COLOR: Color = Color(0.3, 0.65, 0.9, 1.0)

var _hooman: Node = null
var _bg: ColorRect = null
var _fill: ColorRect = null

# Pure-function fill width, identical shape to EnemyHealthBar.fill_width so
# tests can pin the per-bar math without instancing a node.
static func fill_width(hp: int, max_hp: int, bar_width: float) -> float:
	return bar_width * HUD.hp_bar_ratio(hp, max_hp)

# Instantiates and parents a bar to the hooman, mirroring
# EnemyHealthBar.attach's pattern.
static func attach(hooman: Hooman) -> HoomanHealthBar:
	if hooman == null:
		return null
	var bar := HoomanHealthBar.new()
	bar._hooman = hooman
	hooman.add_child(bar)
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

func _process(_dt: float) -> void:
	if _hooman == null or not is_instance_valid(_hooman):
		return
	if _fill != null:
		_fill.size.x = fill_width(_hooman.hp, _hooman.max_hp, BAR_WIDTH)
