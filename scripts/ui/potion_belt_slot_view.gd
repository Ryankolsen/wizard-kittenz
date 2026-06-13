class_name PotionBeltSlotView
extends Control

# Slice 8 of PRD #358. Single 2D slot in the PotionBeltHUD's 1×3 strip.
# Renders potion icon (texture if present, else category-colored placeholder),
# count badge, shared-cooldown sweep, and a disabled tint. Press routes through
# Input.action_press(use_potion_N) so PotionBeltHUD's _poll_inputs picks it up
# on the same frame keyboard presses do — keeps the slot view strict-view with
# no game-state mutation, matching QuickbarSlotView's contract.

const FIRE_GLOW_DURATION: float = 0.25
const COUNT_BADGE_COLOR := Color(0.12, 0.14, 0.22, 0.95)
const COUNT_BADGE_TEXT_COLOR := Color(1, 1, 1, 1)
const DISABLED_TINT := Color(0.4, 0.4, 0.4, 0.7)
const COOLDOWN_OVERLAY := Color(0, 0, 0, 0.55)
const FIRE_GLOW_COLOR := Color(1.0, 0.95, 0.5, 0.85)
# Green-tinted slot chrome so item hotkeys read as distinct from the
# blue-grey ability (quickbar) slots. Same darkness/alpha as the ability
# slots — only the hue shifts.
const EMPTY_PLUS_COLOR := Color(0.72, 0.85, 0.72, 0.6)
const SLOT_BG_COLOR := Color(0.07, 0.14, 0.09, 0.85)
const SLOT_BORDER_COLOR := Color(0.45, 0.75, 0.5, 0.85)

# Category-keyed placeholder colors when PotionDefinition.icon is null. Matches
# the generic potion art palette (red HP / blue MP / green shield) so the
# no-art fallback reads the same as the real bottles. Gold is intentionally
# absent — it is reserved for future special / loot-box potions.
const PLACEHOLDER_HEAL := Color(0.85, 0.25, 0.25, 1.0)
const PLACEHOLDER_MANA := Color(0.3, 0.55, 0.95, 1.0)
const PLACEHOLDER_SHIELD := Color(0.4, 0.8, 0.4, 1.0)

@export var slot_index: int = 1
@export var action_name: StringName = &"use_potion_1"

var _potion_def: PotionDefinition = null
var _state: Dictionary = {"empty": true, "disabled": true, "count": 0, "cooldown_fraction": 0.0, "uses_texture": false, "reason": "empty"}
var _fire_glow: float = 0.0
var _active_touch_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(32, 32)
	if size == Vector2.ZERO:
		size = custom_minimum_size

func set_potion_and_state(def: PotionDefinition, state: Dictionary) -> void:
	_potion_def = def
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
			_press()
		else:
			_release()

func _handle_touch_pressed(event: InputEventScreenTouch) -> void:
	if _active_touch_index != -1:
		return
	if not _point_inside(event.position):
		return
	_active_touch_index = event.index
	_press()

func _handle_touch_released(event: InputEventScreenTouch) -> void:
	if event.index != _active_touch_index:
		return
	_active_touch_index = -1
	_release()

# Empty / disabled slots intentionally still fire the action — PotionBelt.use_slot
# enforces the harmless-mis-tap contract (returns false with no mutation on
# empty / 0-count / cooldown). Routing through Input keeps keyboard + tap on a
# single code path.
func _press() -> void:
	if action_name != &"":
		Input.action_press(action_name)
	queue_redraw()

func _release() -> void:
	if action_name != &"":
		Input.action_release(action_name)
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
	_draw_count_badge()
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
	if _potion_def == null:
		return
	if _state.get("uses_texture", false) and _potion_def.icon != null:
		_draw_texture_aspect_fit(_potion_def.icon, 4.0)
		return
	# Placeholder: colored bottle silhouette as a centered rounded rect. Keeps
	# the no-art path readable at 32px without needing per-potion glyphs.
	var color := _placeholder_color(_potion_def.effect_kind)
	var inner := Rect2(size * 0.25, size * 0.5)
	draw_rect(inner, color, true)

# Draw the icon centered inside the padded box, preserving the texture's aspect
# ratio. autocrop emits varying bottle dimensions (a tall narrow mana vial vs a
# round flask); a plain stretch-to-fill would squash the narrow ones into squat
# blobs, so we letterbox to the box's shorter constraint instead.
func _draw_texture_aspect_fit(tex: Texture2D, pad: float) -> void:
	var box := Rect2(Vector2(pad, pad), size - Vector2(pad * 2.0, pad * 2.0))
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale := minf(box.size.x / tex_size.x, box.size.y / tex_size.y)
	var draw_size := tex_size * scale
	var origin := box.position + (box.size - draw_size) * 0.5
	draw_texture_rect(tex, Rect2(origin, draw_size), false)

func _placeholder_color(kind: int) -> Color:
	match kind:
		PotionDefinition.EffectKind.HEAL_PERCENT:
			return PLACEHOLDER_HEAL
		PotionDefinition.EffectKind.MANA_PERCENT:
			return PLACEHOLDER_MANA
		PotionDefinition.EffectKind.SHIELD:
			return PLACEHOLDER_SHIELD
	return PLACEHOLDER_HEAL

func _draw_cooldown_sweep() -> void:
	var fraction: float = _state.get("cooldown_fraction", 0.0)
	if fraction <= 0.0:
		return
	# Horizontal band — same approximation QuickbarSlotView uses. A true radial
	# sweep would need per-frame polygon math, and the band reads correctly at
	# the 32px slot size.
	var rect := Rect2(Vector2.ZERO, Vector2(size.x, size.y * fraction))
	draw_rect(rect, COOLDOWN_OVERLAY, true)

func _draw_count_badge() -> void:
	var count: int = int(_state.get("count", 0))
	var badge_size := Vector2(16, 10)
	var origin := Vector2(size.x - badge_size.x - 1, size.y - badge_size.y - 1)
	draw_rect(Rect2(origin, badge_size), COUNT_BADGE_COLOR, true)
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 8
	var text := "x%d" % count
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := origin + Vector2((badge_size.x - ts.x) * 0.5, badge_size.y - 1)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COUNT_BADGE_TEXT_COLOR)
