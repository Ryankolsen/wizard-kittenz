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
var _next_floor_button: Button
var _waiting_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headline = $Backdrop/Center/Panel/VBox/Headline
	_floor_label = $Backdrop/Center/Panel/VBox/Stats/FloorLabel
	_enemies_label = $Backdrop/Center/Panel/VBox/Stats/EnemiesLabel
	_xp_label = $Backdrop/Center/Panel/VBox/Stats/XPLabel
	_gold_label = $Backdrop/Center/Panel/VBox/Stats/GoldLabel
	_next_floor_button = $Backdrop/Center/Panel/VBox/ButtonRow/NextFloor
	_waiting_label = $Backdrop/Center/Panel/VBox/ButtonRow/WaitingLabel
	var update_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter
	var exit_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit
	_next_floor_button.pressed.connect(_on_next_floor_pressed)
	update_btn.pressed.connect(_on_update_character_pressed)
	exit_btn.pressed.connect(_on_save_and_exit_pressed)

# PRD #348 / issue #350 — `is_leader` defaults true so solo (and every
# pre-#350 caller) keeps the active "Next Floor" button. Co-op peers
# pass false and get the passive "Waiting for the party leader…" label
# instead; the button is hidden AND disabled so a stray pressed.emit()
# (Godot still fires the signal on hidden buttons) drops at the source.
func populate(summary: FloorRunSummary, message: String, is_leader: bool = true) -> void:
	if _headline == null:
		return
	_headline.text = message
	_floor_label.text = "Floor: %d" % summary.floor_number
	_enemies_label.text = "Enemies Slain: %d" % summary.enemies_slain
	_xp_label.text = "XP Earned: %d" % summary.xp_earned
	_gold_label.text = "Gold Earned: %d" % summary.gold_earned
	_next_floor_button.visible = is_leader
	_next_floor_button.disabled = not is_leader
	_waiting_label.visible = not is_leader

func _on_next_floor_pressed() -> void:
	# Defense-in-depth: a disabled button shouldn't fire pressed in Godot,
	# but pin the no-emit contract here so a future style refactor that
	# leaves the button enabled-but-hidden can't silently re-open the
	# peer-press path.
	if _next_floor_button != null and _next_floor_button.disabled:
		return
	next_floor_pressed.emit()

func _on_update_character_pressed() -> void:
	update_character_pressed.emit()

func _on_save_and_exit_pressed() -> void:
	save_and_exit_pressed.emit()
