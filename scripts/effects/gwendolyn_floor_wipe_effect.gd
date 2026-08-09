class_name GwendolynFloorWipeEffect
extends CanvasLayer

# Issue #478: the visual payoff that plays when an uninterrupted Summon
# Gwendolyn cast (#476) completes — puff-of-smoke arrival, a two-line
# auto-advancing thought bubble, then a full-screen flash. CanvasLayer so it
# renders in screen space regardless of the caster's camera position, same
# reasoning LevelUpEffect (which is world-space, follows the caster instead)
# doesn't apply to a floor-wide effect.
#
# The thought-bubble sequence is embedded here rather than factored into its
# own class: SpeechBubble (scripts/dungeon/speech_bubble.gd) is built around
# a selectable NPCOptionList with player-driven navigation, which is a
# fundamentally different shape than "show line, wait, show next line,
# advance automatically" — pulling out a whole new class for two Label swaps
# would be over-engineering for what this is.
#
# No automated test coverage — VFX/animation timing/UI presentation are
# explicitly out of scope per the issue's testing section. flash_resolved is
# the one seam the gameplay layer (Player) cares about: it fires at the
# flash's visual peak, which is when the floor-wipe kill effect should apply.

signal flash_resolved()
signal sequence_finished()

const SMOKE_DURATION := 0.4
const LINE_DURATION := 1.4
const FLASH_DURATION := 0.3

const LINE_1 := "When you're a hammer.."
const LINE_2 := "Everything lookths like a nail!"

const _GWENDOLYN_TEXTURE = preload("res://assets/sprites/gwendolyn_right.png")

var _sprite: TextureRect
var _label: Label
var _flash_rect: ColorRect

func _ready() -> void:
	layer = 100
	_build_ui()

func _build_ui() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color.WHITE
	_flash_rect.modulate.a = 0.0
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_sprite = TextureRect.new()
	_sprite.texture = _GWENDOLYN_TEXTURE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_sprite.set_anchors_preset(Control.PRESET_CENTER)
	_sprite.modulate.a = 0.0
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sprite)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position.y = 48.0
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

# Runs the full sequence, then frees itself. Fire-and-forget from the
# caller's perspective (called without await) — flash_resolved is the only
# signal the gameplay layer needs to wait on.
func play() -> void:
	await _play_smoke()
	await _play_line(LINE_1)
	await _play_line(LINE_2)
	_label.visible = false
	await _play_flash()
	sequence_finished.emit()
	queue_free()

func _play_smoke() -> void:
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 1.0, SMOKE_DURATION).from(0.0)
	tw.parallel().tween_property(_sprite, "scale", Vector2.ONE, SMOKE_DURATION).from(Vector2(0.4, 0.4))
	await tw.finished

func _play_line(text: String) -> void:
	_label.text = text
	_label.visible = true
	await get_tree().create_timer(LINE_DURATION).timeout

func _play_flash() -> void:
	var tw_in := create_tween()
	tw_in.tween_property(_flash_rect, "modulate:a", 1.0, FLASH_DURATION * 0.5)
	await tw_in.finished
	flash_resolved.emit()
	var tw_out := create_tween()
	tw_out.tween_property(_flash_rect, "modulate:a", 0.0, FLASH_DURATION * 0.5)
	await tw_out.finished
