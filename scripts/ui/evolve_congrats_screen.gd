class_name EvolveCongratsScreen
extends CanvasLayer

# PRD #439 / issue #441 — overlay shown after a Shop class-tier upgrade
# (Kitten -> Cat). Cloned in shape from CongratulationsScreen/DailyLoginPopup:
# CanvasLayer + dimmed backdrop ColorRect + centered PanelContainer,
# process_mode = PROCESS_MODE_ALWAYS. This slice is the static display only —
# populate() sets text/textures/rows immediately, no tween sequencing (#442).
# Continue emits `dismissed`; the caller owns removal.

signal dismissed

var _headline: Label
var _tier_name: Label
var _old_sprite: TextureRect
var _new_sprite: TextureRect
var _stat_delta_list: VBoxContainer
var _continue_button: Button

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

func _populate_stat_delta_list(old_stats: Dictionary, new_stats: Dictionary) -> void:
	for child in _stat_delta_list.get_children():
		child.queue_free()
	for entry in StatDelta.compute(old_stats, new_stats):
		var row := Label.new()
		var delta: float = entry["delta"]
		var sign_str := "+" if delta >= 0 else ""
		row.text = "%s: %s -> %s (%s%s)" % [entry["label"], entry["old_value"], entry["new_value"], sign_str, delta]
		_stat_delta_list.add_child(row)

func _on_continue_pressed() -> void:
	dismissed.emit()
