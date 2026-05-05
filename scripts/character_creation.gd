class_name CharacterCreation
extends Control

# Three-pane character-creation flow.
#  - MainMenu: two buttons ("Quick Start" / "Customize Your Kitten").
#  - QuickStart: class roster; one tap picks a class with a random
#    silly name and enters the game (2-tap path from issue #5).
#  - Customize: name input (with Random suggest), appearance picker
#    (numeric index into the future sprite sheet), class roster.
# Save state is restored before any UI shows; if a save already exists
# the picker is skipped and we drop straight into the main scene so
# progression carries across sessions.

@export var main_scene_path: String = "res://scenes/main.tscn"
# Range of valid sprite-sheet indices for the appearance picker. There's
# no real sprite sheet yet, so the picker just round-trips the integer
# through CharacterData.appearance_index. When art lands, swap APPEARANCE_MAX
# for the actual frame count and add a TextureRect preview here.
const APPEARANCE_MAX: int = 7

@onready var _main_menu: Control = $MainMenu
@onready var _quick_start_panel: Control = $QuickStart
@onready var _customize_panel: Control = $Customize

@onready var _quick_start_button: Button = $MainMenu/VBox/QuickStartButton
@onready var _customize_button: Button = $MainMenu/VBox/CustomizeButton

@onready var _qs_mage_button: Button = $QuickStart/VBox/Buttons/MageButton
@onready var _qs_thief_button: Button = $QuickStart/VBox/Buttons/ThiefButton
@onready var _qs_ninja_button: Button = $QuickStart/VBox/Buttons/NinjaButton
@onready var _qs_back_button: Button = $QuickStart/VBox/BackButton

@onready var _custom_name_edit: LineEdit = $Customize/VBox/NameRow/NameEdit
@onready var _custom_random_name_button: Button = $Customize/VBox/NameRow/RandomNameButton
@onready var _custom_appearance_label: Label = $Customize/VBox/AppearanceRow/AppearanceLabel
@onready var _custom_appearance_prev: Button = $Customize/VBox/AppearanceRow/PrevButton
@onready var _custom_appearance_next: Button = $Customize/VBox/AppearanceRow/NextButton
@onready var _custom_mage_button: Button = $Customize/VBox/Buttons/MageButton
@onready var _custom_thief_button: Button = $Customize/VBox/Buttons/ThiefButton
@onready var _custom_ninja_button: Button = $Customize/VBox/Buttons/NinjaButton
@onready var _custom_back_button: Button = $Customize/VBox/BackButton

var _suggester: NameSuggester = NameSuggester.new()
var _current_appearance: int = 0

func _ready() -> void:
	# If a save was already restored into GameState, skip the picker entirely
	# so progression carries across sessions. Add a "New Character" path later
	# (likely on the main HUD) once save-slot UI lands with #15.
	if GameState.current_character != null:
		get_tree().change_scene_to_file(main_scene_path)
		return

	_quick_start_button.pressed.connect(_show_quick_start)
	_customize_button.pressed.connect(_show_customize)

	_qs_mage_button.pressed.connect(_on_quick_start_class.bind("mage"))
	_qs_thief_button.pressed.connect(_on_quick_start_class.bind("thief"))
	_qs_ninja_button.pressed.connect(_on_quick_start_class.bind("ninja"))
	_qs_back_button.pressed.connect(_show_main_menu)

	_custom_random_name_button.pressed.connect(_on_random_name)
	_custom_appearance_prev.pressed.connect(_on_appearance_prev)
	_custom_appearance_next.pressed.connect(_on_appearance_next)
	_custom_mage_button.pressed.connect(_on_customize_class.bind("mage"))
	_custom_thief_button.pressed.connect(_on_customize_class.bind("thief"))
	_custom_ninja_button.pressed.connect(_on_customize_class.bind("ninja"))
	_custom_back_button.pressed.connect(_show_main_menu)

	_apply_unlock_gates()
	_show_main_menu()

func _apply_unlock_gates() -> void:
	# Ninja is gated on dungeons_completed >= 5 by default; gate both the
	# Quick Start and Customize ninja buttons so the picker is consistent.
	var ninja_unlocked: bool = GameState.unlock_registry.is_unlocked(
		"ninja", GameState.meta_tracker)
	_qs_ninja_button.disabled = not ninja_unlocked
	_custom_ninja_button.disabled = not ninja_unlocked

func _show_main_menu() -> void:
	_main_menu.visible = true
	_quick_start_panel.visible = false
	_customize_panel.visible = false

func _show_quick_start() -> void:
	_main_menu.visible = false
	_quick_start_panel.visible = true
	_customize_panel.visible = false

func _show_customize() -> void:
	_main_menu.visible = false
	_quick_start_panel.visible = false
	_customize_panel.visible = true
	if _custom_name_edit.text.strip_edges() == "":
		_custom_name_edit.text = _suggester.get_random_name()
	_refresh_appearance_label()

func _on_quick_start_class(class_name_str: String) -> void:
	var data := QuickStartController.create_for_class(class_name_str)
	_finalize(data)

func _on_customize_class(class_name_str: String) -> void:
	var typed := _custom_name_edit.text.strip_edges()
	var n := typed if typed != "" else _suggester.get_random_name()
	var data := CharacterFactory.create_default(class_name_str, n)
	data.appearance_index = _current_appearance
	_finalize(data)

func _on_random_name() -> void:
	_custom_name_edit.text = _suggester.get_random_name()

func _on_appearance_prev() -> void:
	_current_appearance = (_current_appearance - 1 + APPEARANCE_MAX) % APPEARANCE_MAX
	_refresh_appearance_label()

func _on_appearance_next() -> void:
	_current_appearance = (_current_appearance + 1) % APPEARANCE_MAX
	_refresh_appearance_label()

func _refresh_appearance_label() -> void:
	_custom_appearance_label.text = "Appearance %d/%d" % [
		_current_appearance + 1, APPEARANCE_MAX
	]

func _finalize(data: CharacterData) -> void:
	GameState.set_character(data)
	SaveManager.save(data, SaveManager.DEFAULT_PATH, GameState.skill_tree, GameState.meta_tracker, GameState.token_inventory, GameState.offline_xp_tracker)
	get_tree().change_scene_to_file(main_scene_path)

# Kept for backwards compatibility with existing tests / call sites.
# New flow uses CharacterFactory.create_default and QuickStartController
# directly; this thin wrapper preserves the old API surface.
static func select_class(klass: CharacterData.CharacterClass, character_name: String = "Kitten") -> CharacterData:
	return CharacterData.make_new(klass, character_name)
