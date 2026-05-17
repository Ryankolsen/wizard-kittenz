class_name CongratulationsScreen
extends CanvasLayer

# PRD #132 / issue #135 — overlay shown on dungeon floor clear in place
# of the previous direct-to-pause-menu jump. Owns no game state: the
# caller (main_scene) builds the FloorRunSummary and headline string,
# then calls populate() and connects the three button signals to its
# own handlers.
#
# CanvasLayer so the dungeon stays visible behind the panel and the
# screen doesn't disrupt the scene tree mid-completion. Buttons emit
# typed signals rather than acting directly — handler wiring lives in
# main_scene per the slice split (#135 Next Floor, #136 Update Character,
# #137 Save & Exit).

signal next_floor_pressed
signal update_character_pressed
signal save_and_exit_pressed

var _headline: Label
var _floor_label: Label
var _enemies_label: Label
var _xp_label: Label
var _gold_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headline = $Backdrop/Center/Panel/VBox/Headline
	_floor_label = $Backdrop/Center/Panel/VBox/Stats/FloorLabel
	_enemies_label = $Backdrop/Center/Panel/VBox/Stats/EnemiesLabel
	_xp_label = $Backdrop/Center/Panel/VBox/Stats/XPLabel
	_gold_label = $Backdrop/Center/Panel/VBox/Stats/GoldLabel
	var next_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/NextFloor
	var update_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter
	var exit_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit
	next_btn.pressed.connect(_on_next_floor_pressed)
	update_btn.pressed.connect(_on_update_character_pressed)
	exit_btn.pressed.connect(_on_save_and_exit_pressed)

func populate(summary: FloorRunSummary, message: String) -> void:
	if _headline == null:
		return
	_headline.text = message
	_floor_label.text = "Floor: %d" % summary.floor_number
	_enemies_label.text = "Enemies Slain: %d" % summary.enemies_slain
	_xp_label.text = "XP Earned: %d" % summary.xp_earned
	_gold_label.text = "Gold Earned: %d" % summary.gold_earned

func _on_next_floor_pressed() -> void:
	next_floor_pressed.emit()

func _on_update_character_pressed() -> void:
	update_character_pressed.emit()

func _on_save_and_exit_pressed() -> void:
	save_and_exit_pressed.emit()
