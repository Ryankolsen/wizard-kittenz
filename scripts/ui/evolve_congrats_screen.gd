class_name EvolveCongratsScreen
extends CanvasLayer

# PRD #439 / issue #441/#442 — overlay shown after a Shop class-tier upgrade
# (Kitten -> Cat). Cloned in shape from CongratulationsScreen/DailyLoginPopup:
# CanvasLayer + dimmed backdrop ColorRect + centered PanelContainer,
# process_mode = PROCESS_MODE_ALWAYS. populate() sets text/textures/rows
# immediately, then _play_transformation() runs the tween-based "anime
# power-up reveal" (old sprite fades/scales down -> flash beat -> new sprite
# tweens in), mirroring ShopScreen._flash_row's signal-for-observability
# pattern instead of asserting tween internals directly.
# Continue emits `dismissed`; the caller owns removal.

signal dismissed
signal transformation_finished

const _FADE_OUT_DURATION := 0.25
const _FLASH_DURATION := 0.15
const _FADE_IN_DURATION := 0.3

var _headline: Label
var _tier_name: Label
var _old_sprite: TextureRect
var _new_sprite: TextureRect
var _stat_delta_list: VBoxContainer
var _continue_button: Button
var _flash_overlay: ColorRect
var _transformation_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_node_or_null("Backdrop") == null:
		# Constructed via EvolveCongratsScreen.new() rather than loaded from
		# evolve_congrats_screen.tscn (e.g. in tests) — build the same node
		# shape in code so populate() has somewhere to write.
		_build_fallback_scene()
	_headline = $Backdrop/Center/Panel/VBox/Headline
	_tier_name = $Backdrop/Center/Panel/VBox/TierName
	_old_sprite = $Backdrop/Center/Panel/VBox/SpriteRow/OldSprite
	_new_sprite = $Backdrop/Center/Panel/VBox/SpriteRow/NewSprite
	_stat_delta_list = $Backdrop/Center/Panel/VBox/StatDeltaList
	_continue_button = $Backdrop/Center/Panel/VBox/ContinueButton
	_flash_overlay = $FlashOverlay
	_continue_button.pressed.connect(_on_continue_pressed)

func _build_fallback_scene() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "Center"
	backdrop.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)
	var headline := Label.new()
	headline.name = "Headline"
	vbox.add_child(headline)
	var tier_name := Label.new()
	tier_name.name = "TierName"
	vbox.add_child(tier_name)
	var sprite_row := HBoxContainer.new()
	sprite_row.name = "SpriteRow"
	vbox.add_child(sprite_row)
	var old_sprite := TextureRect.new()
	old_sprite.name = "OldSprite"
	sprite_row.add_child(old_sprite)
	var new_sprite := TextureRect.new()
	new_sprite.name = "NewSprite"
	sprite_row.add_child(new_sprite)
	var stat_delta_list := VBoxContainer.new()
	stat_delta_list.name = "StatDeltaList"
	vbox.add_child(stat_delta_list)
	var continue_button := Button.new()
	continue_button.name = "ContinueButton"
	vbox.add_child(continue_button)
	var flash_overlay := ColorRect.new()
	flash_overlay.name = "FlashOverlay"
	flash_overlay.color = Color(1, 1, 1, 0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_overlay)

# Safe to call before _ready — defers via call_deferred, matching
# DailyLoginPopup.populate's null-guard pattern.
func populate(old_class: int, new_class: int, old_stats: Dictionary, new_stats: Dictionary) -> void:
	if _headline == null:
		call_deferred("populate", old_class, new_class, old_stats, new_stats)
		return
	_headline.text = "Your kitten has grown into a cat!"
	_tier_name.text = CharacterGrid.class_display_name(new_class)
	_old_sprite.texture = load(SpriteHelper.path_for_class(old_class))
	_new_sprite.texture = load(SpriteHelper.path_for_class(new_class))
	_populate_stat_delta_list(old_stats, new_stats)
	_play_transformation()

func _populate_stat_delta_list(old_stats: Dictionary, new_stats: Dictionary) -> void:
	for child in _stat_delta_list.get_children():
		child.queue_free()
	for entry in StatDelta.compute(old_stats, new_stats):
		var row := Label.new()
		var delta: float = entry["delta"]
		var sign_str := "+" if delta >= 0 else ""
		row.text = "%s: %s -> %s (%s%s)" % [entry["label"], entry["old_value"], entry["new_value"], sign_str, delta]
		_stat_delta_list.add_child(row)

# Anime power-up reveal: old sprite fades/scales down -> flash beat ->
# new sprite tweens in. Runs automatically once per populate() call; killing
# any in-flight tween first keeps a re-populate from stacking sequences.
func _play_transformation() -> void:
	if _transformation_tween != null and _transformation_tween.is_valid():
		_transformation_tween.kill()
	_old_sprite.modulate = Color(1, 1, 1, 1)
	_old_sprite.scale = Vector2.ONE
	_new_sprite.modulate = Color(1, 1, 1, 0)
	_new_sprite.scale = Vector2.ONE
	_flash_overlay.color.a = 0.0
	_continue_button.disabled = true

	_transformation_tween = create_tween()
	_transformation_tween.tween_property(_old_sprite, "modulate:a", 0.0, _FADE_OUT_DURATION)
	_transformation_tween.parallel().tween_property(_old_sprite, "scale", Vector2(0.6, 0.6), _FADE_OUT_DURATION)
	_transformation_tween.tween_property(_flash_overlay, "color:a", 0.8, _FLASH_DURATION * 0.5)
	_transformation_tween.tween_property(_flash_overlay, "color:a", 0.0, _FLASH_DURATION * 0.5)
	_transformation_tween.tween_property(_new_sprite, "modulate:a", 1.0, _FADE_IN_DURATION)
	_transformation_tween.parallel().tween_property(_new_sprite, "scale", Vector2(1.1, 1.1), _FADE_IN_DURATION * 0.5)
	_transformation_tween.chain().tween_property(_new_sprite, "scale", Vector2.ONE, _FADE_IN_DURATION * 0.5)
	_transformation_tween.chain().tween_callback(_on_transformation_finished)

func _on_transformation_finished() -> void:
	_continue_button.disabled = false
	transformation_finished.emit()

func _on_continue_pressed() -> void:
	dismissed.emit()
