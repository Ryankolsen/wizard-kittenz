class_name QuickbarSlotView
extends Control

const _SlotIconFactoryScript := preload("res://scripts/ui/slot_icon_factory.gd")

# Slice 3 of PRD #210. Single 2D slot in the QuickbarHUD's 2×2 grid.
# Renders icon + cooldown sweep + MP badge + disabled tint + fire glow.
# Press routes to Input.action_press(cast_slot_N) so QuickbarController
# (slice 2) handles the actual cast dispatch — keeps the HUD a strict
# view, no game-state mutation.
#
# Touch (mobile) is captured at _input level for press-leave-fire shape
# matching TouchActionButton. Mouse hover + long-press surface a tooltip
# label sibling that the HUD parent positions.

signal empty_slot_pressed(slot: int)

const FIRE_GLOW_DURATION: float = 0.25
const LONG_PRESS_SECONDS: float = 0.5
const MP_BADGE_COLOR := Color(0.3, 0.45, 0.95, 1.0)
const MP_BADGE_TEXT_COLOR := Color(1, 1, 1, 1)
const DISABLED_TINT := Color(0.4, 0.4, 0.4, 0.7)
const READY_TINT := Color(1, 1, 1, 1)
const COOLDOWN_OVERLAY := Color(0, 0, 0, 0.55)
const FIRE_GLOW_COLOR := Color(1.0, 0.95, 0.5, 0.85)
const EMPTY_PLUS_COLOR := Color(0.8, 0.8, 0.85, 0.6)
const SLOT_BG_COLOR := Color(0.08, 0.10, 0.16, 0.85)
const SLOT_BORDER_COLOR := Color(0.55, 0.6, 0.75, 0.85)
const LETTER_COLOR := Color(1, 1, 1, 0.95)

@export var slot_index: int = 1
@export var action_name: StringName = &"cast_slot_1"

var _spell: Spell = null
var _state: Dictionary = {"empty": true, "disabled": true, "cooldown_fraction": 0.0, "show_mp_badge": false, "mp_cost": 0, "reason": "empty"}
var _fire_glow: float = 0.0
var _active_touch_index: int = -1
var _press_start_ms: int = 0
var _tooltip_shown: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(40, 40)
	if size == Vector2.ZERO:
		size = custom_minimum_size

func set_spell_and_state(spell: Spell, state: Dictionary) -> void:
	_spell = spell
	_state = state
	queue_redraw()

func play_fire_highlight() -> void:
	_fire_glow = FIRE_GLOW_DURATION
	queue_redraw()

func _process(dt: float) -> void:
	if _fire_glow > 0.0:
		_fire_glow = maxf(0.0, _fire_glow - dt)
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_pressed(event)
		else:
			_handle_touch_released(event)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release()

func _handle_touch_pressed(event: InputEventScreenTouch) -> void:
	if _active_touch_index != -1:
		return
	if not _point_inside(event.position):
		return
	_active_touch_index = event.index
	_press(event.position - global_position)

func _handle_touch_released(event: InputEventScreenTouch) -> void:
	if event.index != _active_touch_index:
		return
	_active_touch_index = -1
	_release()

func _press(_local_pos: Vector2) -> void:
	_press_start_ms = Time.get_ticks_msec()
	if _state.get("empty", true):
		# Empty slot: signal to open Skills tab — no Input.action_press so a
		# disabled cast doesn't churn QuickbarController.
		emit_signal("empty_slot_pressed", slot_index)
		return
	if action_name != &"":
		Input.action_press(action_name)
	queue_redraw()

func _release() -> void:
	if action_name != &"" and not _state.get("empty", true):
		Input.action_release(action_name)
	_tooltip_shown = false
	queue_redraw()

func _point_inside(point: Vector2) -> bool:
	return point.x >= global_position.x and point.x <= global_position.x + size.x \
		and point.y >= global_position.y and point.y <= global_position.y + size.y

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, SLOT_BG_COLOR, true)
	draw_rect(rect, SLOT_BORDER_COLOR, false, 1.0)
	if _state.get("empty", true):
		_draw_empty_plus()
		return
	_draw_icon()
	_draw_cooldown_sweep()
	_draw_mp_badge()
	if _state.get("disabled", false):
		draw_rect(rect, DISABLED_TINT, true)
	if _fire_glow > 0.0:
		var alpha := (_fire_glow / FIRE_GLOW_DURATION) * FIRE_GLOW_COLOR.a
		draw_rect(rect, Color(FIRE_GLOW_COLOR.r, FIRE_GLOW_COLOR.g, FIRE_GLOW_COLOR.b, alpha), false, 3.0)

func _draw_empty_plus() -> void:
	var center := size * 0.5
	var arm := mini(int(size.x), int(size.y)) * 0.3
	draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), EMPTY_PLUS_COLOR, 2.0)
	draw_line(center - Vector2(0, arm), center + Vector2(0, arm), EMPTY_PLUS_COLOR, 2.0)

func _draw_icon() -> void:
	if _spell == null:
		return
	var color := _SlotIconFactoryScript.color_for_kind(_spell.effect_kind)
	var center := size * 0.5
	var radius := mini(int(size.x), int(size.y)) * 0.4
	draw_circle(center, radius, color)
	var letter := _SlotIconFactoryScript.letter_for_spell(_spell)
	if letter == "":
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := get_theme_default_font_size()
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center + Vector2(-text_size.x * 0.5, text_size.y * 0.3)
	draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, LETTER_COLOR)

func _draw_cooldown_sweep() -> void:
	var fraction: float = _state.get("cooldown_fraction", 0.0)
	if fraction <= 0.0:
		return
	# Radial sweep: a translucent overlay covers the slot proportional
	# to remaining cooldown. Approximated with a horizontal band rather
	# than a true pie sweep — Godot's draw_arc requires per-frame polygon
	# math and the band is visually adequate at 32px slots.
	var rect := Rect2(Vector2.ZERO, Vector2(size.x, size.y * fraction))
	draw_rect(rect, COOLDOWN_OVERLAY, true)

func _draw_mp_badge() -> void:
	if not _state.get("show_mp_badge", false):
		return
	var cost: int = _state.get("mp_cost", 0)
	var badge_size := Vector2(14, 10)
	var origin := Vector2(size.x - badge_size.x - 1, 1)
	draw_rect(Rect2(origin, badge_size), MP_BADGE_COLOR, true)
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 8
	var text := str(cost)
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := origin + Vector2((badge_size.x - ts.x) * 0.5, badge_size.y - 1)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, MP_BADGE_TEXT_COLOR)
