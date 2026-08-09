class_name CastProgressBar
extends Node2D

# Floating cast-progress bar above the player while a channeled spell
# (cast_time > 0 — introduced for Summon Gwendolyn, issue #476, but generic
# to any future channeled spell) is in progress. Mirrors EnemyHealthBar's
# structure (bg + fill ColorRect, instant-snap fill, no tween) but reads
# Quickbar.is_channeling()/channel_progress()/channel_remaining()/
# channeling_spell() instead of enemy HP, and stays hidden whenever no
# channel is active. Nothing here names a specific spell — the name label
# just mirrors whichever spell's display_name Quickbar reports as
# channeling, so adding a second long-cast spell later needs no UI changes.

const BAR_WIDTH: float = 40.0
const BAR_HEIGHT: float = 5.0
# Player sprites sit centered on the origin; clear the head plus a small gap
# so the bar floats above it without overlapping.
const Y_OFFSET: float = -34.0
const BG_COLOR: Color = Color(0.1, 0.1, 0.1, 0.85)
const FILL_COLOR: Color = Color(0.55, 0.75, 1.0, 1.0)
const LABEL_COLOR: Color = Color(1, 1, 1, 1)

var _player: Node = null
var _bg: ColorRect = null
var _fill: ColorRect = null
var _timer_label: Label = null
var _name_label: Label = null

# Pure-function fill width, kept static so the math is pinnable in unit
# tests without instancing a node (mirrors EnemyHealthBar.fill_width).
static func fill_width(progress: float, bar_width: float) -> float:
	return bar_width * clampf(progress, 0.0, 1.0)

# Pure-function countdown text, e.g. 12.3 -> "12.3s". Static for the same
# testability reason as fill_width.
static func format_remaining(remaining: float) -> String:
	return "%.1fs" % remaining

static func attach(player: Node) -> CastProgressBar:
	if player == null:
		return null
	var bar := CastProgressBar.new()
	bar._player = player
	player.add_child(bar)
	return bar

func _ready() -> void:
	position = Vector2(-BAR_WIDTH * 0.5, Y_OFFSET)
	visible = false
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_fill = ColorRect.new()
	_fill.color = FILL_COLOR
	_fill.size = Vector2(0.0, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 8)
	_timer_label.add_theme_color_override("font_color", LABEL_COLOR)
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_timer_label.add_theme_constant_override("outline_size", 2)
	_timer_label.size = Vector2(BAR_WIDTH, 10)
	_timer_label.position = Vector2(0, BAR_HEIGHT)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer_label)
	# Spell name, shown above the bar (mirrors whichever spell is currently
	# channeling — see class comment).
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 8)
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("outline_size", 2)
	_name_label.size = Vector2(BAR_WIDTH, 10)
	_name_label.position = Vector2(0, -10)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("get_quickbar"):
		return
	var quickbar = _player.get_quickbar()
	var channeling: bool = quickbar != null and quickbar.is_channeling()
	visible = channeling
	if not channeling:
		return
	if _fill != null:
		_fill.size.x = fill_width(quickbar.channel_progress(), BAR_WIDTH)
	if _timer_label != null:
		_timer_label.text = format_remaining(quickbar.channel_remaining())
	if _name_label != null:
		var spell: Spell = quickbar.channeling_spell()
		_name_label.text = spell.display_name if spell != null else ""
