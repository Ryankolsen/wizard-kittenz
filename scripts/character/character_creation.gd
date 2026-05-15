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
@export var lobby_scene_path: String = "res://scenes/lobby.tscn"
# Range of valid sprite-sheet indices for the appearance picker. There's
# no real sprite sheet yet, so the picker just round-trips the integer
# through CharacterData.appearance_index. When art lands, swap APPEARANCE_MAX
# for the actual frame count and add a TextureRect preview here.
const APPEARANCE_MAX: int = 7

@onready var _main_menu: Control = $MainMenu
@onready var _quick_start_panel: Control = $QuickStart
@onready var _customize_panel: Control = $Customize
@onready var _multi_menu: Control = $MultiMenu

@onready var _resume_button: Button = $MainMenu/VBox/ResumeButton
@onready var _quick_start_button: Button = $MainMenu/VBox/QuickStartButton
@onready var _customize_button: Button = $MainMenu/VBox/CustomizeButton
@onready var _multiplayer_button: Button = $MainMenu/VBox/MultiplayerButton
@onready var _shop_button: Button = $MainMenu/VBox/ShopButton
@onready var _overwrite_confirm_panel: Control = $OverwriteConfirmPanel
@onready var _overwrite_confirm_button: Button = $OverwriteConfirmPanel/VBox/Buttons/ConfirmButton
@onready var _overwrite_cancel_button: Button = $OverwriteConfirmPanel/VBox/Buttons/CancelButton

@onready var _multi_create_button: Button = $MultiMenu/VBox/CreateRoomButton
@onready var _multi_code_edit: LineEdit = $MultiMenu/VBox/CodeEdit
@onready var _multi_join_button: Button = $MultiMenu/VBox/JoinRoomButton
@onready var _multi_status_label: Label = $MultiMenu/VBox/StatusLabel
@onready var _multi_back_button: Button = $MultiMenu/VBox/BackButton

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
var _save_exists: bool = false

func _ready() -> void:
	_save_exists = GameState.current_character != null or SaveManager.load() != null
	_resume_button.visible = _save_exists
	_resume_button.pressed.connect(_on_resume_pressed)
	_quick_start_button.pressed.connect(_on_quick_start_pressed)
	_customize_button.pressed.connect(_show_customize)
	_multiplayer_button.pressed.connect(_show_multi_menu)
	_shop_button.pressed.connect(_show_shop)
	_overwrite_confirm_button.pressed.connect(_on_overwrite_confirmed)
	_overwrite_cancel_button.pressed.connect(_show_main_menu)

	_multi_create_button.pressed.connect(_on_create_room_pressed)
	_multi_join_button.pressed.connect(_on_join_room_pressed)
	_multi_back_button.pressed.connect(_show_main_menu)

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
		"ninja", GameState.meta_tracker, GameState.paid_unlocks)
	_qs_ninja_button.disabled = not ninja_unlocked
	_custom_ninja_button.disabled = not ninja_unlocked

func _show_main_menu() -> void:
	_main_menu.visible = true
	_quick_start_panel.visible = false
	_customize_panel.visible = false
	_multi_menu.visible = false
	_overwrite_confirm_panel.visible = false

func _on_resume_pressed() -> void:
	var save_data := SaveManager.load()
	if save_data == null:
		return
	GameState.apply_merged_save(save_data)
	get_tree().change_scene_to_file(main_scene_path)

func _on_quick_start_pressed() -> void:
	if _save_exists:
		_main_menu.visible = false
		_overwrite_confirm_panel.visible = true
	else:
		_show_quick_start()

func _on_overwrite_confirmed() -> void:
	_overwrite_confirm_panel.visible = false
	_show_quick_start()

func _show_multi_menu() -> void:
	_main_menu.visible = false
	_quick_start_panel.visible = false
	_customize_panel.visible = false
	_multi_menu.visible = true
	_multi_status_label.text = ""

func _show_shop() -> void:
	get_tree().change_scene_to_file("res://scenes/shop_screen.tscn")

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
	SaveManager.save(data, SaveManager.DEFAULT_PATH, GameState.skill_tree, GameState.meta_tracker, GameState.offline_xp_tracker, GameState.cosmetic_inventory, GameState.paid_unlocks)
	get_tree().change_scene_to_file(main_scene_path)

func _ensure_character_for_multiplayer() -> CharacterData:
	if GameState.current_character != null:
		return GameState.current_character
	# Quick-start as Mage for multiplayer if no character exists
	var data := QuickStartController.create_for_class("mage")
	GameState.set_character(data)
	SaveManager.save(data, SaveManager.DEFAULT_PATH, GameState.skill_tree, GameState.meta_tracker, GameState.offline_xp_tracker, GameState.cosmetic_inventory, GameState.paid_unlocks)
	return data

func _ensure_session_async() -> NakamaSession:
	if NakamaService.session != null:
		return NakamaService.session
	return await NakamaService.authenticate_device_async(OS.get_unique_id())

func _on_create_room_pressed() -> void:
	_multi_create_button.disabled = true
	_multi_status_label.text = "Connecting…"
	var c := _ensure_character_for_multiplayer()
	var session := await _ensure_session_async()
	if session == null:
		_multi_status_label.text = "Auth failed — check your connection"
		_multi_create_button.disabled = false
		return
	var socket := await NakamaService.create_socket_async(session)
	if socket == null:
		_multi_status_label.text = "Socket failed — check your connection"
		_multi_create_button.disabled = false
		return
	var room_code := RoomCodeGenerator.new().generate()
	var local_player := LobbyPlayer.make(
		session.user_id, c.character_name,
		CharacterData.CharacterClass.keys()[c.character_class], true
	)
	var lobby := NakamaLobby.new(socket, session)
	var ok := await lobby.create_async(room_code, local_player)
	if not ok:
		_multi_status_label.text = "Failed to create room"
		_multi_create_button.disabled = false
		return
	GameState.set_lobby(lobby)
	GameState.local_player_id = session.user_id
	get_tree().change_scene_to_file(lobby_scene_path)

func _on_join_room_pressed() -> void:
	var raw_code := _multi_code_edit.text.strip_edges().to_upper()
	if not RoomCodeValidator.is_valid(raw_code):
		_multi_status_label.text = "Invalid code — must be 5 uppercase letters/digits"
		return
	_multi_join_button.disabled = true
	_multi_status_label.text = "Joining…"
	var c := _ensure_character_for_multiplayer()
	var session := await _ensure_session_async()
	if session == null:
		_multi_status_label.text = "Auth failed — check your connection"
		_multi_join_button.disabled = false
		return
	var socket := await NakamaService.create_socket_async(session)
	if socket == null:
		_multi_status_label.text = "Socket failed — check your connection"
		_multi_join_button.disabled = false
		return
	var local_player := LobbyPlayer.make(
		session.user_id, c.character_name,
		CharacterData.CharacterClass.keys()[c.character_class]
	)
	var lobby := NakamaLobby.new(socket, session)
	var join_error := ""
	lobby.join_failed.connect(func(reason: String) -> void: join_error = reason)
	var ok := await lobby.join_async(raw_code, local_player)
	if not ok:
		_multi_status_label.text = join_error if join_error != "" else "Room not found or full"
		_multi_join_button.disabled = false
		return
	GameState.set_lobby(lobby)
	GameState.local_player_id = session.user_id
	get_tree().change_scene_to_file(lobby_scene_path)

# Kept for backwards compatibility with existing tests / call sites.
# New flow uses CharacterFactory.create_default and QuickStartController
# directly; this thin wrapper preserves the old API surface.
static func select_class(klass: CharacterData.CharacterClass, character_name: String = "Kitten") -> CharacterData:
	return CharacterData.make_new(klass, character_name)
