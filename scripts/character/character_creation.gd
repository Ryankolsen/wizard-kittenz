class_name CharacterCreation
extends Control

# Multi-save character-select flow (PRD #250 / slice 4).
#  - MainMenu now shows a four-card CharacterGrid (one per archetype)
#    bound to SaveSlots.slot_summaries(). Empty card → name-only customize
#    → SaveSlots.create_slot. Occupied card → SlotActionPanel
#    (Continue / New Game / Customize / Back).
#  - QuickStart panel kept in the scene for legacy callers (and existing
#    tests) but no longer shown by the main menu route.
#  - Customize is name-only — the appearance picker was removed in this
#    slice. New characters default appearance_index = 0.

const CharacterGridRef = preload("res://scripts/character/character_grid.gd")
const SaveSlotsRef = preload("res://scripts/core/save_slots.gd")

@export var main_scene_path: String = "res://scenes/main.tscn"
@export var lobby_scene_path: String = "res://scenes/lobby.tscn"

@onready var _main_menu: ScrollContainer = $MainMenu
@onready var _quick_start_panel: Control = $QuickStart
@onready var _customize_panel: Control = $Customize
@onready var _multi_menu: Control = $MultiMenu
@onready var _slot_action_panel: Control = $SlotActionPanel
@onready var _overwrite_confirm_panel: Control = $OverwriteConfirmPanel

@onready var _battle_card: Button = $MainMenu/VBox/CharacterGrid/BattleSlotButton
@onready var _wizard_card: Button = $MainMenu/VBox/CharacterGrid/WizardSlotButton
@onready var _sleepy_card: Button = $MainMenu/VBox/CharacterGrid/SleepySlotButton
@onready var _chonk_card: Button = $MainMenu/VBox/CharacterGrid/ChonkSlotButton
@onready var _multiplayer_button: Button = $MainMenu/VBox/TopButtons/MultiplayerButton
@onready var _shop_button: Button = $MainMenu/VBox/TopButtons/ShopButton
@onready var _main_title: Label = $MainMenu/VBox/Title
@onready var _scroll_hint: Label = $ScrollHint

@onready var _slot_title: Label = $SlotActionPanel/VBox/SlotTitle
@onready var _slot_continue_button: Button = $SlotActionPanel/VBox/ContinueButton
@onready var _slot_new_game_button: Button = $SlotActionPanel/VBox/NewGameButton
@onready var _slot_customize_button: Button = $SlotActionPanel/VBox/SlotCustomizeButton
@onready var _slot_back_button: Button = $SlotActionPanel/VBox/SlotBackButton

@onready var _overwrite_confirm_button: Button = $OverwriteConfirmPanel/VBox/Buttons/ConfirmButton
@onready var _overwrite_cancel_button: Button = $OverwriteConfirmPanel/VBox/Buttons/CancelButton

@onready var _multi_create_button: Button = $MultiMenu/VBox/CreateRoomButton
@onready var _multi_code_edit: LineEdit = $MultiMenu/VBox/CodeEdit
@onready var _multi_join_button: Button = $MultiMenu/VBox/JoinRoomButton
@onready var _multi_status_label: Label = $MultiMenu/VBox/StatusLabel
@onready var _multi_back_button: Button = $MultiMenu/VBox/BackButton

@onready var _qs_battle_button: Button = $QuickStart/VBox/Buttons/BattleKittenGroup/BattleKittenButton
@onready var _qs_wizard_button: Button = $QuickStart/VBox/Buttons/WizardKittenGroup/WizardKittenButton
@onready var _qs_sleepy_button: Button = $QuickStart/VBox/Buttons/SleepyKittenGroup/SleepyKittenButton
@onready var _qs_chonk_button: Button = $QuickStart/VBox/Buttons/ChonkKittenGroup/ChonkKittenButton
@onready var _qs_back_button: Button = $QuickStart/VBox/BackButton

@onready var _custom_name_edit: LineEdit = $Customize/VBox/NameRow/NameEdit
@onready var _custom_random_name_button: Button = $Customize/VBox/NameRow/RandomNameButton
@onready var _custom_save_button: Button = $Customize/VBox/SaveButton
@onready var _custom_back_button: Button = $Customize/VBox/BackButton

var _suggester: NameSuggester = NameSuggester.new()
# Archetype currently selected by a card press. Drives the slot-action panel
# and the customize-save routing (rename existing slot vs. create new).
var _selected_archetype: String = ""
# When true, the customize panel is editing the in-place active character's
# name (preserves xp/level). When false, customize creates a new slot for
# _selected_archetype on save.
var _customize_is_rename: bool = false
# When true, the four-card grid is acting as the co-op picker (issue #255):
# an occupied card switches to that slot and proceeds to the lobby; an empty
# card routes through creation first, then back to the lobby instead of into
# solo play. Toggled by the Multiplayer button, reset on return to main menu.
var _multiplayer_pick_mode: bool = false

func _ready() -> void:
	_battle_card.pressed.connect(_on_card_pressed.bind(SaveBundle.SLOT_BATTLE))
	_wizard_card.pressed.connect(_on_card_pressed.bind(SaveBundle.SLOT_WIZARD))
	_sleepy_card.pressed.connect(_on_card_pressed.bind(SaveBundle.SLOT_SLEEPY))
	_chonk_card.pressed.connect(_on_card_pressed.bind(SaveBundle.SLOT_CHONK))
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_shop_button.pressed.connect(_show_shop)

	_slot_continue_button.pressed.connect(_on_slot_continue_pressed)
	_slot_new_game_button.pressed.connect(_on_slot_new_game_pressed)
	_slot_customize_button.pressed.connect(_on_slot_customize_pressed)
	_slot_back_button.pressed.connect(_show_main_menu)

	_overwrite_confirm_button.pressed.connect(_on_overwrite_confirmed)
	_overwrite_cancel_button.pressed.connect(_show_main_menu)

	_multi_create_button.pressed.connect(_on_create_room_pressed)
	_multi_join_button.pressed.connect(_on_join_room_pressed)
	_multi_back_button.pressed.connect(_show_main_menu)

	# Legacy QuickStart panel — kept in the scene for backward-compat callers
	# and existing tests, but the new MainMenu routes through the card grid.
	_qs_battle_button.pressed.connect(_on_quick_start_class.bind("battle_kitten"))
	_qs_wizard_button.pressed.connect(_on_quick_start_class.bind("wizard_kitten"))
	_qs_sleepy_button.pressed.connect(_on_quick_start_class.bind("sleepy_kitten"))
	_qs_chonk_button.pressed.connect(_on_quick_start_class.bind("chonk_kitten"))
	_qs_back_button.pressed.connect(_show_main_menu)

	_custom_random_name_button.pressed.connect(_on_random_name)
	_custom_save_button.pressed.connect(_on_customize_save)
	_custom_back_button.pressed.connect(_show_main_menu)

	_apply_unlock_gates()
	_refresh_card_grid()
	_show_main_menu()
	_wire_scroll_hint()

	# Daily login streak popup (PRD #237 / issue #244). Deferred so the rest
	# of _ready (menu visibility, button wiring) completes before the popup
	# mounts — matches the PRD's "after load, NOT mid-load" trigger. Gated on
	# current_character so brand-new installs see the popup only after their
	# first character is created and the save round-trips.
	_maybe_show_daily_login_popup.call_deferred()

func _maybe_show_daily_login_popup() -> void:
	if GameState.current_character == null:
		return
	var proxy := KittenSaveData.new()
	proxy.streak_day = GameState.streak_day
	proxy.last_login_date = GameState.last_login_date
	var result: Dictionary = DailyStreakEngine.resolve(proxy, DateToday.iso_today())
	var action := int(result.get("action", DailyStreakEngine.Action.ALREADY_CLAIMED))
	if action == DailyStreakEngine.Action.ALREADY_CLAIMED:
		return
	var popup_scene: PackedScene = load("res://scenes/daily_login_popup.tscn")
	if popup_scene == null:
		return
	var popup: DailyLoginPopup = popup_scene.instantiate()
	add_child(popup)
	popup.populate(result)
	popup.claimed.connect(_on_daily_login_claimed.bind(result, proxy))

func _on_daily_login_claimed(result: Dictionary, proxy: KittenSaveData) -> void:
	GameState.streak_day = proxy.streak_day
	GameState.last_login_date = proxy.last_login_date
	var reward: Dictionary = result.get("reward", {})
	DailyRewardApplier.apply(reward, GameState.currency_ledger, GameState.offline_xp_tracker)
	SaveManager.save_from_state()

func _apply_unlock_gates() -> void:
	var chonk_unlocked: bool = GameState.unlock_registry.is_unlocked(
		"chonk_kitten", GameState.meta_tracker, GameState.paid_unlocks)
	_chonk_card.disabled = not chonk_unlocked

# Bind each archetype card to its current summary. Each card shows a portrait
# (baked in the scene), a name line ("New" when empty), the class name, and a
# level line ("Lv N" only when occupied). Re-runs after any flow that mutates
# the bundle (new-game reset, slot creation) so the labels stay live.
func _refresh_card_grid() -> void:
	var bundle := SaveManager.load_bundle()
	var summaries := SaveSlotsRef.slot_summaries(bundle)
	for entry in summaries:
		var arch: String = entry["archetype"]
		var card := _card_for(arch)
		if card == null:
			continue
		var name_label := card.find_child("NameLabel", true, false) as Label
		var class_label := card.find_child("ClassLabel", true, false) as Label
		var level_label := card.find_child("LevelLabel", true, false) as Label
		if name_label != null:
			name_label.text = CharacterGridRef.card_name_text(entry)
		if class_label != null:
			class_label.text = CharacterGridRef.card_class_text(entry)
		if level_label != null:
			level_label.text = CharacterGridRef.card_level_text(entry)

func _card_for(archetype: String) -> Button:
	match archetype:
		SaveBundle.SLOT_BATTLE: return _battle_card
		SaveBundle.SLOT_WIZARD: return _wizard_card
		SaveBundle.SLOT_SLEEPY: return _sleepy_card
		SaveBundle.SLOT_CHONK: return _chonk_card
	return null

func _show_main_menu() -> void:
	# Returning to the main menu always drops co-op pick mode — backing out of
	# the grid, the lobby create/join panel, or a customize flow re-arms the
	# cards for solo play.
	_set_multiplayer_pick_mode(false)
	_main_menu.visible = true
	_quick_start_panel.visible = false
	_customize_panel.visible = false
	_multi_menu.visible = false
	_slot_action_panel.visible = false
	_overwrite_confirm_panel.visible = false

# Toggles the grid between solo and co-op picker modes. Pressing Multiplayer a
# second time (while still on the grid) cancels back to solo.
func _on_multiplayer_pressed() -> void:
	_set_multiplayer_pick_mode(not _multiplayer_pick_mode)

func _set_multiplayer_pick_mode(on: bool) -> void:
	_multiplayer_pick_mode = on
	if _main_title != null:
		_main_title.text = "Co-op — pick a character" if on else "Wizard Kittenz"
	if _multiplayer_button != null:
		_multiplayer_button.text = "Cancel co-op" if on else "Multiplayer"

func _on_card_pressed(archetype: String) -> void:
	_selected_archetype = archetype
	var bundle := SaveManager.load_bundle()
	if _multiplayer_pick_mode:
		_on_multiplayer_card_pressed(archetype, bundle)
		return
	if SaveSlotsRef.is_occupied(bundle, archetype):
		_show_slot_action_panel(archetype)
	else:
		# Empty card → name-only customize → create_slot on save.
		_customize_is_rename = false
		_show_customize()

# Co-op picker routing (issue #255): an occupied card sets that slot active and
# proceeds to the lobby create/join panel; an empty card can't join, so it
# drops into creation first (staying in pick mode so save returns to the lobby).
func _on_multiplayer_card_pressed(archetype: String, bundle: SaveBundle) -> void:
	if not can_enter_multiplayer(bundle, archetype):
		_customize_is_rename = false
		_show_customize()
		return
	GameState.switch_to_slot(archetype)
	if GameState.current_character == null:
		_show_main_menu()
		return
	_show_multi_menu()

func _show_slot_action_panel(archetype: String) -> void:
	var bundle := SaveManager.load_bundle()
	var slot: CharacterSlotData = bundle.get_slot(archetype)
	if slot == null:
		return
	_slot_title.text = "%s · Lv %d" % [slot.character_name, slot.level]
	_main_menu.visible = false
	_slot_action_panel.visible = true

func _on_slot_continue_pressed() -> void:
	GameState.switch_to_slot(_selected_archetype)
	if GameState.current_character == null:
		_show_main_menu()
		return
	get_tree().change_scene_to_file(main_scene_path)

func _on_slot_new_game_pressed() -> void:
	_slot_action_panel.visible = false
	_overwrite_confirm_panel.visible = true

func _on_slot_customize_pressed() -> void:
	# Rename the existing slot's character — preserves xp/level/skills.
	GameState.switch_to_slot(_selected_archetype)
	_customize_is_rename = true
	_show_customize()

func _show_multi_menu() -> void:
	_main_menu.visible = false
	_quick_start_panel.visible = false
	_customize_panel.visible = false
	_multi_menu.visible = true
	_multi_status_label.text = ""

func _show_shop() -> void:
	get_tree().change_scene_to_file("res://scenes/shop_screen.tscn")

func _show_customize() -> void:
	_main_menu.visible = false
	_quick_start_panel.visible = false
	_slot_action_panel.visible = false
	_overwrite_confirm_panel.visible = false
	_customize_panel.visible = true
	if _custom_name_edit.text.strip_edges() == "":
		_custom_name_edit.text = _suggester.get_random_name()

# Overwrite confirm is now scoped to the selected slot (new-game reset).
# Account-wide currency/cosmetics/unlocks survive — SaveSlots.new_game_reset
# only touches the per-slot CharacterSlotData.
func _on_overwrite_confirmed() -> void:
	var bundle := SaveManager.load_bundle()
	CharacterGridRef.confirm_new_game(bundle, _selected_archetype)
	SaveManager.save_bundle(bundle)
	# Treat the freshly-reset slot as "empty" for the customize flow so save
	# creates the new character from scratch (level 1, fresh skills) rather
	# than renaming the prior occupant.
	_customize_is_rename = false
	_show_customize()

func _on_customize_save() -> void:
	var typed := _custom_name_edit.text.strip_edges()
	var n := typed if typed != "" else _suggester.get_random_name()

	# Path A: in-place rename of the live character (slot Customize action).
	# Preserves xp / level / skills via apply_identity_edit.
	if _customize_is_rename and GameState.current_character != null:
		QuickStartController.apply_identity_edit(GameState.current_character, n, 0)
		SaveManager.save_from_state()
		_refresh_card_grid()
		_show_main_menu()
		return

	# Path B: legacy fallback — script invoked with a live current_character
	# but the new-grid wasn't the entry point (existing test/tooling path).
	# Mirror the prior in-place-rename behavior so existing tests pass.
	if _customize_is_rename == false and _selected_archetype == "" and GameState.current_character != null:
		QuickStartController.apply_identity_edit(GameState.current_character, n, 0)
		SaveManager.save_from_state()
		_show_main_menu()
		return

	# Path C: empty-card OR new-game-reset slot. Create a fresh CharacterData
	# of the selected archetype's Kitten class with appearance_index = 0,
	# hand off to _finalize so the bundle is written and main.tscn loads.
	var arch := _selected_archetype if _selected_archetype != "" else SaveBundle.SLOT_BATTLE
	var klass_name := _class_name_for(arch)
	var data := CharacterFactory.create_default(klass_name, n)
	data.appearance_index = 0
	_finalize(data)

func _class_name_for(archetype: String) -> String:
	match archetype:
		SaveBundle.SLOT_BATTLE: return "battle_kitten"
		SaveBundle.SLOT_WIZARD: return "wizard_kitten"
		SaveBundle.SLOT_SLEEPY: return "sleepy_kitten"
		SaveBundle.SLOT_CHONK: return "chonk_kitten"
	return "battle_kitten"

func _on_quick_start_class(class_name_str: String) -> void:
	var data := QuickStartController.create_for_class(class_name_str)
	_finalize(data)

func _on_random_name() -> void:
	_custom_name_edit.text = _suggester.get_random_name()

func _finalize(data: CharacterData) -> void:
	GameState.set_character(data)
	GameState.dungeon_run_controller = null
	# Co-op picker created an empty slot's character: persist it as a real
	# bundle slot (so its progress is the active slot for co-op rewards) and
	# return to the lobby create/join panel rather than launching solo play.
	if _multiplayer_pick_mode:
		SaveManager.save_from_state()
		_refresh_card_grid()
		_show_multi_menu()
		return
	SaveManager.save_from_state()
	get_tree().change_scene_to_file(main_scene_path)

func _ensure_session_async() -> NakamaSession:
	if NakamaService.session != null:
		return NakamaService.session
	return await NakamaService.authenticate_device_async(_resolved_device_id())

# Issue #404: on record where OS.get_unique_id() returns "" (Godot's support
# varies per platform, notably iOS), user:// stores a generated UUID so the
# device still gets a stable Nakama identity across restarts.
const DEVICE_ID_FALLBACK_PATH: String = "user://device_id_fallback.txt"

# Test injection seam for _raw_device_id() — defaults to the real OS call so
# tests can stub an empty return without depending on the platform's actual
# get_unique_id() support.
var _device_id_provider: Callable = Callable(OS, "get_unique_id")

# Dev-time fan-out for local multi-client testing: when two Godot instances
# run on the same machine, OS.get_unique_id() returns the same value and both
# authenticate as the same Nakama user — collapsing the match to one presence
# and breaking position/enemy sync. In debug builds we append a per-process
# suffix so every launched instance (editor play button, multiple-instances
# debug, exported debug build) claims a distinct Nakama identity. Honors an
# explicit override via --device-suffix=<s> or WIZARD_DEVICE_SUFFIX so manual
# testers can pin reproducible identities across restarts. Release builds
# always return the raw device id so a real player's account persists.
func _resolved_device_id() -> String:
	var base: String = _raw_device_id()
	if not OS.is_debug_build():
		return base
	var suffix: String = ""
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--device-suffix="):
			suffix = arg.substr("--device-suffix=".length())
			break
	if suffix == "" and OS.has_environment("WIZARD_DEVICE_SUFFIX"):
		suffix = OS.get_environment("WIZARD_DEVICE_SUFFIX")
	if suffix == "":
		suffix = "pid" + str(OS.get_process_id())
	return base + "-" + suffix

# Raw device-ID lookup, falling back to a persisted generated UUID when the
# platform's OS.get_unique_id() comes back empty. Kept separate from
# _resolved_device_id() so tests can stub _device_id_provider without
# depending on the real platform return value.
func _raw_device_id() -> String:
	var base: String = _device_id_provider.call()
	if base != "":
		return base
	return _fallback_device_id(DEVICE_ID_FALLBACK_PATH)

func _fallback_device_id(path: String) -> String:
	var persisted := _read_persisted_uuid(path)
	if persisted != "":
		return persisted
	var generated := _generate_uuid()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(generated)
	return generated

func _read_persisted_uuid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()

# UUID v4 (RFC 4122): 16 random bytes with the version/variant nibbles fixed.
func _generate_uuid() -> String:
	var b := PackedByteArray()
	for i in range(16):
		b.append(randi() % 256)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var hex := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]

func _on_create_room_pressed() -> void:
	var c := GameState.current_character
	if c == null:
		_multi_status_label.text = "Pick a character first"
		return
	_multi_create_button.disabled = true
	_multi_status_label.text = "Connecting…"
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
		CharacterData.class_name_for(c.character_class), true,
		c.character_class
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
	var c := GameState.current_character
	if c == null:
		_multi_status_label.text = "Pick a character first"
		return
	_multi_join_button.disabled = true
	_multi_status_label.text = "Joining…"
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
		CharacterData.class_name_for(c.character_class), false,
		c.character_class
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

# Multiplayer-entry guard (issue #255). The four-card grid doubles as the
# co-op picker: an occupied slot proceeds to the lobby, an empty slot must
# create a character first (no joining with no character). Pure-data so the
# guard contract is unit-testable without booting the scene; the card handler
# routes on the result.
static func can_enter_multiplayer(bundle: SaveBundle, archetype: String) -> bool:
	return SaveSlotsRef.is_occupied(bundle, archetype)

# Kept for backwards compatibility with existing tests / call sites.
# New flow uses CharacterFactory.create_default and QuickStartController
# directly; this thin wrapper preserves the old API surface.
static func select_class(klass: CharacterData.CharacterClass, character_name: String = "Kitten") -> CharacterData:
	return CharacterData.make_new(klass, character_name)

# Scroll-down indicator on the main menu. The CharacterGrid's lower row
# (Sleepy/Chonk) sits below the fold on short viewports, and the default
# scrollbar is easy to miss — this floating hint at the bottom-center pulses
# while there's more to scroll and hides itself at the bottom or when the
# main menu is not the active panel.
func _wire_scroll_hint() -> void:
	if _scroll_hint == null or _main_menu == null:
		return
	var vbar := _main_menu.get_v_scroll_bar()
	if vbar != null:
		vbar.value_changed.connect(func(_v: float) -> void: _update_scroll_hint())
		vbar.changed.connect(_update_scroll_hint)
	_main_menu.resized.connect(_update_scroll_hint)
	_main_menu.visibility_changed.connect(_update_scroll_hint)
	var tween := create_tween().set_loops()
	tween.tween_property(_scroll_hint, "modulate:a", 0.45, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_scroll_hint, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	_update_scroll_hint.call_deferred()

func _update_scroll_hint() -> void:
	if _scroll_hint == null or _main_menu == null:
		return
	if not _main_menu.visible:
		_scroll_hint.visible = false
		return
	var vbar := _main_menu.get_v_scroll_bar()
	if vbar == null:
		_scroll_hint.visible = false
		return
	_scroll_hint.visible = (vbar.max_value - vbar.page) > (vbar.value + 1.0)
