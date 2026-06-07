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
const _QuickbarScript := preload("res://scripts/character/quickbar.gd")

# Slice 4 of PRD #210. The Skills tab needs a Quickbar to render the
# `[1] [2] [3] [4]` assignment row. In real play we walk get_nodes_in_group
# ("player") to fetch Player.get_quickbar(); in tests bind_quickbar(qb)
# injects one directly so test cases don't need to instance a Player scene.
var _quickbar = null

# Slice 9 of PRD #358 (issue #366). The Items tab renders one row per owned
# potion with a 3-button assignment cluster bound to the local player's
# PotionBelt. Resolved off the player group by default; tests inject directly
# via bind_potion_belt / bind_consumable_inventory.
var _potion_belt: PotionBelt = null
var _consumable_inventory: ConsumableInventory = null

# PRD #353 slice 3 (#356). Tap-to-reveal color key for the Skills tab,
# mirroring the stat-tier legend in StatsTabPanel: a flat toggle button
# whose body (the 3-entry category grid) is hidden by default and shown
# on press. Built once in _ready and inserted into SkillsPanel between
# SkillPointsLabel and SkillsList.
var _skills_legend_toggle: Button = null
var _skills_legend: GridContainer = null

const _SKILLS_LEGEND_ORDER: Array = [
	SkillCategory.Category.ATTACK,
	SkillCategory.Category.HEALING,
	SkillCategory.Category.PROTECT,
]

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
	var items_tab := find_child("ItemsTabButton", true, false) as Button
	if items_tab != null:
		items_tab.pressed.connect(_on_items_tab_pressed)
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
	_install_skills_legend()

# Inserts the Skills tab color key (toggle + collapsed legend body) into
# SkillsPanel between SkillPointsLabel and SkillsList. Mirrors the stats
# tab legend's interaction and styling (issue #356 / commits 2d5664a,
# ada3414) — same flat toggle, ⓘ + ▾/▴ caret, hidden-by-default 2-column
# grid at a reduced font so it stays inside the panel width.
func _install_skills_legend() -> void:
	var panel := find_child("SkillsPanel", true, false) as VBoxContainer
	if panel == null:
		return
	var skills_list := panel.get_node_or_null("SkillsList") as Node
	_skills_legend_toggle = Button.new()
	_skills_legend_toggle.name = "SkillsLegendToggle"
	_skills_legend_toggle.toggle_mode = true
	_skills_legend_toggle.flat = true
	_skills_legend_toggle.focus_mode = Control.FOCUS_NONE
	_skills_legend_toggle.toggled.connect(_on_skills_legend_toggled)
	var toggle_bar := HBoxContainer.new()
	toggle_bar.name = "SkillsLegendToggleBar"
	toggle_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	toggle_bar.add_child(_skills_legend_toggle)
	panel.add_child(toggle_bar)
	_skills_legend = _make_skills_legend()
	_skills_legend.visible = false
	panel.add_child(_skills_legend)
	# Place toggle + legend just above SkillsList so the key sits between
	# the skill-points header and the list of rows it explains.
	if skills_list != null:
		var list_index := skills_list.get_index()
		panel.move_child(toggle_bar, list_index)
		panel.move_child(_skills_legend, list_index + 1)
	_update_skills_legend_toggle_text()

func _make_skills_legend() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "SkillsLegend"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	for category in _SKILLS_LEGEND_ORDER:
		var lbl := Label.new()
		lbl.name = "SkillsLegend_%d" % category
		lbl.text = "%s %s" % [String.chr(0x25CF), SkillCategory.label_for_category(category)]
		lbl.modulate = SkillCategory.color_for_category(category)
		lbl.add_theme_font_size_override("font_size", 13)
		grid.add_child(lbl)
	return grid

func _on_skills_legend_toggled(pressed: bool) -> void:
	if _skills_legend != null:
		_skills_legend.visible = pressed
	_update_skills_legend_toggle_text()

func _update_skills_legend_toggle_text() -> void:
	if _skills_legend_toggle == null:
		return
	var caret := "▴" if _skills_legend_toggle.button_pressed else "▾"
	_skills_legend_toggle.text = "%s Color key %s" % [String.chr(0x24D8), caret]

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
	_set_touch_controls_hidden(true)
	_show_main_menu()
	if not is_multiplayer():
		get_tree().paused = true

# Hides (or restores) the gameplay touch overlay while the menu is open.
# The overlay shares CanvasLayer.layer with this menu, so on touch platforms
# its QuickbarHUD slots render on top of the panel and intercept taps on the
# Stats-tab "+" buttons. No-op when no TouchControls are in the tree (tests,
# desktop builds where the overlay is hidden anyway).
func _set_touch_controls_hidden(hidden: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for tc in tree.get_nodes_in_group(&"touch_controls"):
		if tc.has_method("set_menu_open"):
			tc.set_menu_open(hidden)

func close() -> void:
	_set_touch_controls_hidden(false)
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
# Lands on the Items (Inventory) tab by default per PRD #268 — the visual
# avatar there is the most informative landing view. Stats/Skills tabs
# remain reachable via the tab buttons. The dungeon-transition flow
# overrides this and switches back to Stats explicitly.
func open_character_submenu() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = true
	_show_inventory_tab()
	_refresh_equipment_panel()
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
	_set_touch_controls_hidden(true)
	open_character_submenu()
	# open_character_submenu lands on the Items tab by default; the
	# transition flow needs the Stats tab so the player sees the
	# Continue button and any unspent points to allocate.
	_show_stats_tab()
	_refresh_character_stats()
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
	_set_touch_controls_hidden(false)
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
		# Co-op (#337): leaving the dungeon must also leave the Nakama match
		# so the remaining players receive a presence-leave and despawn our
		# kitten. Mirrors the lobby screen's leave (lobby.gd _on_leave_pressed);
		# without this the leaver's RemoteKitten lingers on every peer's screen.
		# Fire-and-forget — the scene change below doesn't wait on the socket.
		if gs.lobby != null:
			gs.lobby.leave_async()
			gs.set_lobby(null)
		# Tear down the co-op session so a subsequent solo run doesn't think
		# it's still multiplayer (is_multiplayer reads coop_session). end() is
		# idempotent, so a pre-handshake / already-ended session is safe.
		if gs.coop_session != null:
			gs.coop_session.end()
			gs.coop_session = null
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
	_refresh_class_label(_current_character())

func _refresh_class_label(character: CharacterData) -> void:
	var label := find_child("ClassLabel", true, false) as Label
	if label == null:
		return
	if character == null:
		label.text = ""
		return
	var raw: String = CharacterData.class_name_for(character.character_class)
	label.text = raw.replace("_", " ").to_lower().capitalize()

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
	_set_tab_visible("ItemsPanel", false)

func _show_skills_tab() -> void:
	_set_tab_visible("StatsPanel", false)
	_set_tab_visible("SkillsPanel", true)
	_set_tab_visible("InventoryTab", false)
	_set_tab_visible("ItemsPanel", false)

func _show_inventory_tab() -> void:
	_set_tab_visible("StatsPanel", false)
	_set_tab_visible("SkillsPanel", false)
	_set_tab_visible("InventoryTab", true)
	_set_tab_visible("ItemsPanel", false)

func _show_items_tab() -> void:
	_set_tab_visible("StatsPanel", false)
	_set_tab_visible("SkillsPanel", false)
	_set_tab_visible("InventoryTab", false)
	_set_tab_visible("ItemsPanel", true)

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
	# PRD #353 slice 2 (#355): category-colored dot at the start of the row
	# (gray for locked / passive-no-spell), with the name tinted to match.
	var colors := SkillCategory.row_colors(node.unlocked, node.spell)
	var dot := Label.new()
	dot.name = "SkillRowDot_%s" % node.id
	dot.text = "●"
	dot.add_theme_color_override("font_color", colors["dot"])
	row.add_child(dot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.name = "SkillRowLabel_%s" % node.id
	label.add_theme_color_override("font_color", colors["name"])
	# Per #130: locked rows advertise the level required to auto-unlock the
	# node — skills are no longer purchased with skill points. Unlocked
	# rows keep the "Unlocked" status suffix so existing visual contracts
	# (and tests / future polish) still have a stable token to read.
	if node.unlocked:
		label.text = "%s — %s" % [node.display_name, _assignment_label_text(node)]
	else:
		label.text = "%s — Unlocks at level %d" % [node.display_name, node.level_required]
	col.add_child(label)
	if node.description != "":
		var desc := Label.new()
		desc.name = "SkillRowDesc_%s" % node.id
		desc.text = node.description
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(desc)
	row.add_child(col)
	# Slice 4 of PRD #210. Unlocked rows that grant a spell get the
	# [1] [2] [3] [4] assignment cluster. Locked rows (and unlock rows that
	# happen to have no spell, e.g. a passive node) keep the legacy label-
	# only layout — assignment controls would be meaningless without a
	# spell to bind, and locked rows explicitly must not have any per AC.
	if node.unlocked and node.spell != null:
		row.add_child(_make_assign_cluster(node.spell))
	return row

func _make_assign_cluster(spell: Spell) -> HBoxContainer:
	var cluster := HBoxContainer.new()
	cluster.name = "AssignCluster"
	for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
		var btn := Button.new()
		btn.name = "assign_slot_%d" % i
		btn.text = str(i)
		btn.toggle_mode = true
		btn.button_pressed = _slot_holds_spell(i, spell)
		# Bind the slot index + spell into the lambda so a single handler can
		# route every per-row press without juggling node names.
		var slot_n := i
		btn.pressed.connect(func() -> void: _on_assign_slot_pressed(slot_n, spell))
		cluster.add_child(btn)
	return cluster

# Returns the live "Slot N" / "Unassigned" suffix used in the unlocked-row
# label so user story 12 (current assignment visible in Skills tab) is
# satisfied without forcing the reader to scan the highlighted button.
func _assignment_label_text(node: SkillNode) -> String:
	var qb = _resolve_quickbar()
	if qb == null or node.spell == null:
		return "Unlocked"
	for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
		if qb.get_slot(i) == node.spell:
			return "Slot %d" % i
	return "Unassigned"

func _slot_holds_spell(slot_n: int, spell: Spell) -> bool:
	var qb = _resolve_quickbar()
	if qb == null:
		return false
	return qb.get_slot(slot_n) == spell

# Toggle-style press: re-tapping the slot the spell already occupies
# unassigns it (user story 13). Otherwise route through Quickbar.assign
# which handles the swap-with-existing case (user story 14) on its own.
# Updates row visuals in-place rather than rebuilding — destroying the
# button mid-press emits "freed while signal emitting" engine errors.
func _on_assign_slot_pressed(slot_n: int, spell: Spell) -> void:
	var qb = _resolve_quickbar()
	if qb == null:
		return
	if qb.get_slot(slot_n) == spell:
		qb.unassign(slot_n)
	else:
		qb.assign(slot_n, spell)
	_refresh_assign_visuals()

# Walks every SkillRow_* in SkillsList and re-syncs each assign_slot_N
# button's checked state plus the row's "— Slot N / Unassigned" suffix.
# Cheap (≤ 5 rows × 4 buttons) and avoids the rebuild path's free-during-
# signal-emission hazard.
func _refresh_assign_visuals() -> void:
	var list := find_child("SkillsList", true, false) as VBoxContainer
	if list == null:
		return
	var tree := _current_skill_tree()
	if tree == null:
		return
	for row in list.get_children():
		var sid := String(row.name).trim_prefix("SkillRow_")
		var node := tree.find(sid)
		if node == null or not node.unlocked or node.spell == null:
			continue
		var label := row.find_child("SkillRowLabel_%s" % sid, true, false) as Label
		if label != null:
			label.text = "%s — %s" % [node.display_name, _assignment_label_text(node)]
		for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
			var btn := row.find_child("assign_slot_%d" % i, true, false) as Button
			if btn != null:
				btn.set_pressed_no_signal(_slot_holds_spell(i, node.spell))

# Test-friendly seam: lets a test push a Quickbar in without instancing a
# Player scene + adding it to a "player" group. Mirrors QuickbarHUD's
# bind_player.
func bind_quickbar(qb) -> void:
	_quickbar = qb

# Items-tab injection seams parallel to bind_quickbar. The real path resolves
# both off GameState in _refresh_items_panel; tests skip GameState by binding
# in pure data classes.
func bind_potion_belt(belt: PotionBelt) -> void:
	_potion_belt = belt

func bind_consumable_inventory(inv: ConsumableInventory) -> void:
	_consumable_inventory = inv

# Pure helper — true iff slot_n of belt holds potion_id. Mirrors
# _slot_holds_spell but takes the belt explicitly so the Items-tab tests don't
# need a scene instance to assert the toggle-state contract (issue #366).
static func _slot_holds_potion(belt: PotionBelt, slot_n: int, potion_id: String) -> bool:
	if belt == null:
		return false
	return belt.get_slot(slot_n) == potion_id

# Pure helper — toggle-press routing parallel to _on_assign_slot_pressed. If
# the slot already holds this potion the press unassigns; otherwise it routes
# through PotionBelt.assign (which handles the swap-with-existing case on its
# own, same as Quickbar.assign).
static func _on_potion_assign_slot_pressed(belt: PotionBelt, slot_n: int, potion_id: String) -> void:
	if belt == null:
		return
	if belt.get_slot(slot_n) == potion_id:
		belt.unassign(slot_n)
	else:
		belt.assign(slot_n, potion_id)

# Pure helper — list of {id, def, count} for every potion the player owns (count
# > 0), iterated in PotionCatalog.all() order so a new catalog entry shows up
# in the Items tab without a UI change. Empty array on null inventory.
static func _owned_potion_rows(inventory: ConsumableInventory) -> Array:
	var out: Array = []
	if inventory == null:
		return out
	for def in PotionCatalog.all():
		var count := inventory.count_of(def.id)
		if count <= 0:
			continue
		out.append({"id": def.id, "def": def, "count": count})
	return out

func _resolve_quickbar():
	if _quickbar != null:
		return _quickbar
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if p.has_method("get_quickbar"):
			return p.get_quickbar()
	return null

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

func _on_items_tab_pressed() -> void:
	_show_items_tab()
	_refresh_items_panel()

# Rebuilds the Items tab from GameState (or the test-injected belt / inventory).
# One row per owned potion; each row carries a 3-button assignment cluster
# routing through PotionBelt via _on_potion_assign_slot_pressed. Empty-state
# message shows when the player owns nothing — mirrors the Skills tab's
# "no skills unlocked yet" affordance shape.
func _refresh_items_panel() -> void:
	var list := find_child("ItemsList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	var inv := _resolve_consumable_inventory()
	var belt := _resolve_potion_belt()
	var rows := _owned_potion_rows(inv)
	var empty_label := find_child("ItemsEmpty", true, false) as Label
	if empty_label != null:
		empty_label.visible = rows.is_empty()
	for row_data in rows:
		list.add_child(_make_potion_row(row_data, belt))

func _make_potion_row(row_data: Dictionary, belt: PotionBelt) -> HBoxContainer:
	var potion_id: String = row_data["id"]
	var def: PotionDefinition = row_data["def"]
	var count: int = row_data["count"]
	var row := HBoxContainer.new()
	row.name = "PotionRow_%s" % potion_id
	row.add_theme_constant_override("separation", 8)
	if def.icon != null:
		row.add_child(_make_potion_row_icon(potion_id, def))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.name = "PotionRowLabel_%s" % potion_id
	name_label.text = "%s  x%d" % [def.display_name, count]
	col.add_child(name_label)
	if def.description != "":
		var desc := Label.new()
		desc.name = "PotionRowDesc_%s" % potion_id
		desc.text = def.description
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(desc)
	row.add_child(col)
	row.add_child(_make_potion_assign_cluster(potion_id, belt))
	return row

# Leading icon for a potion row — the generic per-kind bottle carried on
# def.icon (sourced from PotionImageResolver). Fixed square, aspect-fit so the
# narrow mana vial keeps its proportions, nearest filter to preserve the
# pixel-art crispness. Only added when the potion actually has art.
func _make_potion_row_icon(potion_id: String, def: PotionDefinition) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "PotionRowIcon_%s" % potion_id
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = def.icon
	return icon

func _make_potion_assign_cluster(potion_id: String, belt: PotionBelt) -> HBoxContainer:
	var cluster := HBoxContainer.new()
	cluster.name = "PotionAssignCluster"
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		var btn := Button.new()
		btn.name = "potion_assign_slot_%d" % i
		btn.text = str(i)
		btn.toggle_mode = true
		btn.button_pressed = _slot_holds_potion(belt, i, potion_id)
		var slot_n := i
		var pid := potion_id
		btn.pressed.connect(func() -> void: _on_potion_row_slot_pressed(slot_n, pid))
		cluster.add_child(btn)
	return cluster

# Routes a per-row button press into the pure helper, then refreshes the
# tab so every row's button state reflects the new belt layout (a swap on
# one row flips a button on another row). Mirrors _refresh_assign_visuals's
# in-place refresh shape, but cheaper given ≤3 rows × 3 buttons.
func _on_potion_row_slot_pressed(slot_n: int, potion_id: String) -> void:
	var belt := _resolve_potion_belt()
	if belt == null:
		return
	_on_potion_assign_slot_pressed(belt, slot_n, potion_id)
	_refresh_items_panel()

func _resolve_potion_belt() -> PotionBelt:
	if _potion_belt != null:
		return _potion_belt
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.potion_belt

func _resolve_consumable_inventory() -> ConsumableInventory:
	if _consumable_inventory != null:
		return _consumable_inventory
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.consumable_inventory

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
