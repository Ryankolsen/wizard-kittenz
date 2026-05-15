class_name PauseMenu
extends CanvasLayer

# Pause overlay (PRD #42, walking skeleton in #44, Character submenu in
# #47, Skills tab in #48). Owns its own visibility + the get_tree().paused
# flag in solo mode, plus a root-menu / Character-submenu swap inside the
# existing CenterContainer. The Character submenu itself swaps between
# Stats / Skills / Inventory tabs via TabBar buttons.
#
# Solo (GameState.coop_session == null or inactive):
#   open() sets get_tree().paused = true so enemies + the player freeze
#   close() clears it
#
# Multiplayer (CoopSession active):
#   open() shows the overlay only; the tree keeps ticking, the local
#   player remains vulnerable, remote players are unaffected. Host-
#   initiated party-wide pause is tracked separately in #43.
#
# process_mode = PROCESS_MODE_ALWAYS is set on the scene root so the
# Resume button still receives input while the tree is paused (default
# PROCESS_MODE_INHERIT would freeze the menu alongside the rest of the
# scene, leaving the player stuck on a paused screen with no way out).

signal resumed
# Re-emitted from StatsTabPanel.continue_pressed (PRD #52 / #61). Fires
# when the dungeon-transition flow's Continue button is pressed —
# main_scene listens for this to resume dungeon loading after the player
# has had a chance to spend any unspent stat points.
signal transition_continued

# True while open_for_dungeon_transition is active. Guards close() so that
# pressing Back → Resume (bypassing the Continue button) still fires
# transition_continued rather than silently stranding the player on the
# Room Clear screen.
var _transition_mode: bool = false

const AudioSettings := preload("res://scripts/core/audio_settings_manager.gd")
const ControlsSettings := preload("res://scripts/core/controls_settings_manager.gd")
const QuitHandler := preload("res://scripts/dungeon/quit_dungeon_handler.gd")
const StatsTabPanelScript := preload("res://scripts/ui/stats_tab_panel.gd")
const EquipmentTabPanelScript := preload("res://scripts/ui/equipment_tab_panel.gd")

func _ready() -> void:
	visible = false
	var resume_btn := find_child("Resume", true, false) as Button
	if resume_btn != null:
		resume_btn.pressed.connect(_on_resume_pressed)
	var character_btn := find_child("Character", true, false) as Button
	if character_btn != null:
		character_btn.pressed.connect(_on_character_pressed)
	var back_btn := find_child("Back", true, false) as Button
	if back_btn != null:
		back_btn.pressed.connect(_on_back_pressed)
	var settings_btn := find_child("Settings", true, false) as Button
	if settings_btn != null:
		settings_btn.pressed.connect(_on_settings_pressed)
	var settings_back := find_child("SettingsBack", true, false) as Button
	if settings_back != null:
		settings_back.pressed.connect(_on_settings_back_pressed)
	var bgm_slider := find_child("BGMSlider", true, false) as HSlider
	if bgm_slider != null:
		bgm_slider.value_changed.connect(_on_bgm_slider_changed)
	var sfx_slider := find_child("SFXSlider", true, false) as HSlider
	if sfx_slider != null:
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	var stats_tab := find_child("StatsTabButton", true, false) as Button
	if stats_tab != null:
		stats_tab.pressed.connect(_on_stats_tab_pressed)
	var skills_tab := find_child("SkillsTabButton", true, false) as Button
	if skills_tab != null:
		skills_tab.pressed.connect(_on_skills_tab_pressed)
	var inventory_tab := find_child("InventoryTabButton", true, false) as Button
	if inventory_tab != null:
		inventory_tab.pressed.connect(_on_inventory_tab_pressed)
	var layout_opt := find_child("LayoutOption", true, false) as OptionButton
	if layout_opt != null:
		layout_opt.item_selected.connect(_on_layout_option_selected)
	var quit_btn := find_child("QuitDungeon", true, false) as Button
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit_dungeon_pressed)
	var quit_confirm := find_child("QuitConfirm", true, false) as Button
	if quit_confirm != null:
		quit_confirm.pressed.connect(_on_quit_confirm_pressed)
	var quit_cancel := find_child("QuitCancel", true, false) as Button
	if quit_cancel != null:
		quit_cancel.pressed.connect(_on_quit_cancel_pressed)
	var host_pause_toggle := find_child("HostPauseToggle", true, false) as Button
	if host_pause_toggle != null:
		host_pause_toggle.pressed.connect(_on_host_pause_toggle_pressed)

func _process(_dt: float) -> void:
	_update_stats_tab_badge()

# Polls current_character.skill_points each frame and toggles the Stats
# tab badge (#58). Same polling shape as HUD._update_stat_points_badge —
# the badge updates within one frame of a level-up or a StatAllocator
# spend. Cheap: one find_child + one read off CharacterData.
func _update_stats_tab_badge() -> void:
	var badge := find_child("StatsTabBadge", true, false) as Label
	if badge == null:
		return
	var c := _current_character()
	if c == null:
		badge.visible = false
		return
	badge.visible = StatBadge.should_show(c.skill_points)

func open() -> void:
	visible = true
	_show_main_menu()
	if not is_multiplayer():
		get_tree().paused = true

func close() -> void:
	# If the player presses Back → Resume while in transition mode, treat it
	# the same as pressing Continue so the dungeon-load flow is not stranded.
	if _transition_mode:
		_transition_mode = false
		var panel := find_child("StatsPanel", true, false) as StatsTabPanelScript
		if panel != null:
			panel.set_continue_visible(false)
		visible = false
		if not _is_host_paused():
			get_tree().paused = false
		transition_continued.emit()
		return
	visible = false
	# Clear the local soft-pause flag — UNLESS a host-initiated party-wide
	# pause is active (#43). The host opening their own PauseMenu after
	# pressing "Pause for everyone" would otherwise silently unfreeze the
	# tree locally on Resume without sending OP_HOST_UNPAUSE, desyncing
	# the host from the remote clients still frozen behind the wire flag.
	if not _is_host_paused():
		get_tree().paused = false
	resumed.emit()

# Reads the lobby's host-pause flag through GameState. Returns false on every
# fall-through (no autoload / no lobby / null state) so the solo path keeps
# the existing "Resume always unpauses" contract.
func _is_host_paused() -> bool:
	var lobby := _current_lobby()
	if lobby == null or lobby.host_pause_state == null:
		return false
	return lobby.host_pause_state.is_paused()

func _current_lobby() -> NakamaLobby:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.lobby

# True when there is an active CoopSession on GameState. Used by open()
# to decide whether to pause the tree. Returns false on every fall-
# through path (no autoload / no session / inactive session) so solo
# behavior is the default — the safer choice on every error edge.
func is_multiplayer() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var session: CoopSession = gs.coop_session
	if session == null:
		return false
	return session.is_active()

# Opens the Character submenu directly. Hides the root menu's buttons,
# shows the CharacterSubmenu panel, and refreshes the stat labels from
# GameState.current_character. Safe to call without first calling open()
# — tests exercise the submenu independently of the root open flow.
# Always lands on the Stats tab so a player re-entering the submenu gets
# a predictable starting view rather than wherever they were last time.
func open_character_submenu() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = true
	_show_stats_tab()
	_refresh_character_stats()

# Opens the pause menu in dungeon-transition mode (PRD #52 / #61). Lands
# directly on the Stats tab with the Continue button visible so the player
# can spend unspent points before the next dungeon loads. In solo play the
# tree pauses just like a normal open() so combat doesn't continue while
# the player is allocating; in multiplayer the tree keeps ticking.
# Continue press fires transition_continued — main_scene listens for that
# to drive the actual scene reload.
func open_for_dungeon_transition() -> void:
	_transition_mode = true
	open_character_submenu()
	if not is_multiplayer():
		get_tree().paused = true
	var panel := find_child("StatsPanel", true, false) as StatsTabPanelScript
	if panel == null:
		return
	panel.set_continue_visible(true)
	if not panel.continue_pressed.is_connected(_on_transition_continue_pressed):
		panel.continue_pressed.connect(_on_transition_continue_pressed)

func _on_transition_continue_pressed() -> void:
	_transition_mode = false
	var panel := find_child("StatsPanel", true, false) as StatsTabPanelScript
	if panel != null:
		panel.set_continue_visible(false)
	visible = false
	if not _is_host_paused():
		get_tree().paused = false
	transition_continued.emit()

# Opens the Character submenu pre-switched to the Skills tab. Mirrors
# open_character_submenu's "make-it-visible-from-anywhere" contract so
# tests can exercise the panel without first navigating through the
# root menu + Character button + Skills tab chain.
func open_skills_panel() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = true
	_show_skills_tab()
	_refresh_skills_panel()

func close_character_submenu() -> void:
	_show_main_menu()

# Opens the Settings submenu (PRD #42 / #49). Hides MainMenu and the
# Character submenu, shows SettingsSubmenu, and pre-populates the
# sliders from the persisted audio settings so the player sees the
# current state rather than the .tscn default (1.0). Safe to call
# without first calling open() — tests exercise the submenu directly.
func open_settings_submenu() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var character := find_child("CharacterSubmenu", true, false) as Control
	if character != null:
		character.visible = false
	var settings := find_child("SettingsSubmenu", true, false) as Control
	if settings != null:
		settings.visible = true
	_load_audio_settings_into_sliders()
	_load_controls_layout_into_option()

func close_settings_submenu() -> void:
	_show_main_menu()

func _show_main_menu() -> void:
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = true
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = false
	var settings := find_child("SettingsSubmenu", true, false) as Control
	if settings != null:
		settings.visible = false
	var quit_dialog := find_child("QuitConfirmDialog", true, false) as Control
	if quit_dialog != null:
		quit_dialog.visible = false
	_refresh_host_pause_toggle()

# Updates the host-only "Pause/Unpause for everyone" button (#43). The
# button is only visible when there is an active lobby and the local player
# is the host (lobby creator). Label flips based on the current
# host_pause_state so a paused host sees "Unpause for everyone" — closes
# the toggle loop. Re-runs every time the root menu is shown so opening
# the menu picks up state changes from the wire (e.g. host-disconnect
# auto-release while the host's own pause menu was already open).
func _refresh_host_pause_toggle() -> void:
	var btn := find_child("HostPauseToggle", true, false) as Button
	if btn == null:
		return
	var lobby := _current_lobby()
	if lobby == null or not lobby.is_local_host():
		btn.visible = false
		return
	btn.visible = true
	var paused := lobby.host_pause_state != null and lobby.host_pause_state.is_paused()
	btn.text = "Unpause for everyone" if paused else "Pause for everyone"

func _on_host_pause_toggle_pressed() -> void:
	var lobby := _current_lobby()
	if lobby == null or not lobby.is_local_host():
		return
	# Toggle on the live state, not the button label, so a race where the
	# label was rendered against a stale wire state still routes to the
	# correct op. is_paused() is the single source of truth.
	if lobby.host_pause_state != null and lobby.host_pause_state.is_paused():
		lobby.send_host_unpause_async()
	else:
		lobby.send_host_pause_async()
	_refresh_host_pause_toggle()

# Opens the Quit-Dungeon confirmation dialog (PRD #42 / #45). Hides the
# main menu and shows the dialog. The Message label is swapped for the
# multiplayer wording ("Leave party?") so the user understands the
# multiplayer branch doesn't save — that decision is in
# QuitDungeonHandler. Safe to call without first calling open() — tests
# exercise the dialog directly.
func open_quit_confirm_dialog() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var dialog := find_child("QuitConfirmDialog", true, false) as Control
	if dialog != null:
		dialog.visible = true
	var msg := find_child("Message", true, false) as Label
	if msg != null:
		msg.text = "Leave party?" if is_multiplayer() else "Save and exit?"

# Cancels the confirmation and returns to the root menu. Pure UI swap —
# no save, no scene change, no unpause beyond what close()/open() owns.
func cancel_quit_confirm_dialog() -> void:
	_show_main_menu()

# Confirms the quit. Routes the save-vs-skip branch through
# QuitDungeonHandler and then changes the scene to character_creation.
# Always clears get_tree().paused first — change_scene_to_file works
# from a paused tree but the destination scene shouldn't inherit the
# paused flag.
func confirm_quit_dungeon() -> void:
	QuitHandler.save_and_exit(_current_coop_session())
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.current_character = null
		gs.skill_tree = null
		gs.dungeon_run_controller = null
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")

func _current_coop_session() -> CoopSession:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.coop_session

# Reads the persisted audio settings and pushes them into the slider
# values. Also applies them to AudioServer so the live volume matches
# what the sliders show — covers the case where the submenu is opened
# before apply_loaded() has run at app start.
func _load_audio_settings_into_sliders() -> void:
	var loaded := AudioSettings.load_settings()
	var bgm_slider := find_child("BGMSlider", true, false) as HSlider
	var sfx_slider := find_child("SFXSlider", true, false) as HSlider
	# set_value_no_signal so populating the slider doesn't fire
	# _on_bgm_slider_changed → re-save → re-apply cycle on every open.
	if bgm_slider != null:
		bgm_slider.set_value_no_signal(loaded["bgm"])
	if sfx_slider != null:
		sfx_slider.set_value_no_signal(loaded["sfx"])
	AudioSettings.set_bgm_volume(loaded["bgm"])
	AudioSettings.set_sfx_volume(loaded["sfx"])

# Mirrors _load_audio_settings_into_sliders for the Controls section.
# Reads the persisted layout and selects the matching OptionButton item
# without firing item_selected, so populating doesn't trigger a save
# cycle on every submenu open.
func _load_controls_layout_into_option() -> void:
	var opt := find_child("LayoutOption", true, false) as OptionButton
	if opt == null:
		return
	var layout := ControlsSettings.load_layout()
	var idx := 1 if layout == ControlsSettings.LAYOUT_RIGHT_HAND else 0
	opt.select(idx)

func _on_layout_option_selected(index: int) -> void:
	var layout := ControlsSettings.LAYOUT_RIGHT_HAND if index == 1 else ControlsSettings.LAYOUT_LEFT_HAND
	ControlsSettings.save_layout(layout)

func _on_bgm_slider_changed(value: float) -> void:
	AudioSettings.set_bgm_volume(value)
	_persist_audio_sliders()

func _on_sfx_slider_changed(value: float) -> void:
	AudioSettings.set_sfx_volume(value)
	_persist_audio_sliders()

func _persist_audio_sliders() -> void:
	var bgm_slider := find_child("BGMSlider", true, false) as HSlider
	var sfx_slider := find_child("SFXSlider", true, false) as HSlider
	var bgm := bgm_slider.value if bgm_slider != null else AudioSettings.DEFAULT_BGM
	var sfx := sfx_slider.value if sfx_slider != null else AudioSettings.DEFAULT_SFX
	AudioSettings.save_settings({"bgm": bgm, "sfx": sfx})

# Delegates the per-stat render to the StatsTabPanel script attached to
# the StatsPanel node (#60). The panel builds its own rows + "+" buttons
# and reads through StatAllocator; this method's job is just to push the
# current CharacterData in. Safe with a null character — the panel falls
# back to em-dash placeholders.
func _refresh_character_stats() -> void:
	var panel := find_child("StatsPanel", true, false) as StatsTabPanelScript
	if panel == null:
		return
	panel.refresh(_current_character())

func _current_character() -> CharacterData:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.current_character

func _current_skill_tree() -> SkillTree:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.skill_tree

# Toggles tab visibility inside the Character submenu. Each helper hides
# the other tabs and shows its own — kept as three small functions
# rather than one with a parameter because the call sites read more
# clearly ("open Stats" vs "open Skills") and the extra dispatch is
# free against three Control nodes.
func _show_stats_tab() -> void:
	_set_tab_visible("StatsPanel", true)
	_set_tab_visible("SkillsPanel", false)
	_set_tab_visible("InventoryTab", false)

func _show_skills_tab() -> void:
	_set_tab_visible("StatsPanel", false)
	_set_tab_visible("SkillsPanel", true)
	_set_tab_visible("InventoryTab", false)

func _show_inventory_tab() -> void:
	_set_tab_visible("StatsPanel", false)
	_set_tab_visible("SkillsPanel", false)
	_set_tab_visible("InventoryTab", true)

func _set_tab_visible(node_name: String, vis: bool) -> void:
	var n := find_child(node_name, true, false) as Control
	if n != null:
		n.visible = vis

# Renders the Skills tab from GameState. The SkillPointsLabel always
# reads the live current_character.skill_points; the SkillsList is
# rebuilt from scratch each refresh so unlock state changes (and the
# resulting enable/disable on the per-row Unlock button) propagate
# without manual diffing. Cheap — the tree is three nodes per class.
func _refresh_skills_panel() -> void:
	var c := _current_character()
	var tree := _current_skill_tree()
	var sp_label := find_child("SkillPointsLabel", true, false) as Label
	if sp_label != null:
		if c == null:
			sp_label.text = "Skill Points: —"
		else:
			sp_label.text = "Skill Points: %d" % c.skill_points
	var list := find_child("SkillsList", true, false) as VBoxContainer
	if list == null:
		return
	# Synchronous free (not queue_free) so the old rows leave the tree
	# before the new ones are added. queue_free defers to end-of-frame,
	# which leaves the old rows around long enough for find_child to
	# pick up a stale "Locked" label after a same-frame unlock —
	# tripping #48's "unlocked label says Unlocked" contract. UI rows
	# carry no async state, so free() is safe.
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	if tree == null:
		return
	var manager: SkillTreeManager = null
	if c != null:
		manager = SkillTreeManager.make(tree, c)
	for n in tree.all_nodes():
		list.add_child(_make_skill_row(n, manager))

func _make_skill_row(node: SkillNode, _manager: SkillTreeManager) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "SkillRow_%s" % node.id
	var label := Label.new()
	label.name = "SkillRowLabel_%s" % node.id
	# Per #130: locked rows advertise the level required to auto-unlock the
	# node — skills are no longer purchased with skill points. Unlocked
	# rows keep the "Unlocked" status suffix so existing visual contracts
	# (and tests / future polish) still have a stable token to read.
	if node.unlocked:
		label.text = "%s — Unlocked" % node.display_name
	else:
		label.text = "%s — Unlocks at level %d" % [node.display_name, node.level_required]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

func _on_resume_pressed() -> void:
	close()

func _on_character_pressed() -> void:
	open_character_submenu()

func _on_back_pressed() -> void:
	close_character_submenu()

func _on_stats_tab_pressed() -> void:
	_show_stats_tab()
	_refresh_character_stats()

func _on_skills_tab_pressed() -> void:
	_show_skills_tab()
	_refresh_skills_panel()

func _on_inventory_tab_pressed() -> void:
	_show_inventory_tab()
	_refresh_equipment_panel()

# Pushes GameState.item_inventory + current_character into the
# EquipmentTabPanel script attached to the InventoryTab node (#82).
# Called whenever the Inventory tab is shown so the panel reflects the
# current loadout — including any items the player picked up between
# pause-menu opens.
func _refresh_equipment_panel() -> void:
	var panel := find_child("InventoryTab", true, false) as EquipmentTabPanelScript
	if panel == null:
		return
	var gs := get_node_or_null("/root/GameState")
	var inv: ItemInventory = null
	if gs != null:
		inv = gs.item_inventory
	panel.refresh(inv, _current_character())

func _on_settings_pressed() -> void:
	open_settings_submenu()

func _on_settings_back_pressed() -> void:
	close_settings_submenu()

func _on_quit_dungeon_pressed() -> void:
	open_quit_confirm_dialog()

func _on_quit_confirm_pressed() -> void:
	confirm_quit_dungeon()

func _on_quit_cancel_pressed() -> void:
	cancel_quit_confirm_dialog()
