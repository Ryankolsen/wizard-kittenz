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

const AudioSettings := preload("res://scripts/audio_settings_manager.gd")

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

func open() -> void:
	visible = true
	_show_main_menu()
	if not is_multiplayer():
		get_tree().paused = true

func close() -> void:
	visible = false
	# Always clear the pause flag on close, even in multiplayer — open()
	# only sets it in solo, so a multiplayer close() is a no-op against
	# a flag that was already false. Cheaper than re-evaluating
	# is_multiplayer() at close time, and robust if the player tabs into
	# multiplayer mid-pause via a future debug toggle.
	get_tree().paused = false
	resumed.emit()

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

# Spend one skill point to unlock node_id, via SkillTreeManager so the
# can_unlock gate (prereqs + points + already-unlocked) is shared with
# the rest of the codebase. Returns true on success. Refreshes the
# panel on success so the SkillPointsLabel and per-node state reflect
# the new world immediately.
func try_unlock_skill(node_id: String) -> bool:
	var c := _current_character()
	var tree := _current_skill_tree()
	if c == null or tree == null:
		return false
	var manager := SkillTreeManager.make(tree, c)
	var ok := manager.unlock(node_id)
	if ok:
		_refresh_skills_panel()
	return ok

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

# Pulls live values off GameState.current_character into the stat labels.
# Missing character (pre-creation / cleared GameState) falls back to em-
# dash placeholders so the labels never read as zeroed real values.
# Mirrors the HUD's HP/XP bar polling style: a single render call from
# the open path, no per-frame loop — the menu is a static snapshot, not
# a live readout (the dungeon is paused in solo, and a multiplayer
# player can close and re-open to refresh).
func _refresh_character_stats() -> void:
	var c := _current_character()
	var level_label := find_child("LevelLabel", true, false) as Label
	var hp_label := find_child("HPLabel", true, false) as Label
	var mp_label := find_child("MPLabel", true, false) as Label
	var atk_label := find_child("ATKLabel", true, false) as Label
	var def_label := find_child("DEFLabel", true, false) as Label
	var spd_label := find_child("SPDLabel", true, false) as Label
	if c == null:
		if level_label != null: level_label.text = "Lv —"
		if hp_label != null: hp_label.text = "HP —/—"
		if mp_label != null: mp_label.text = "MP —"
		if atk_label != null: atk_label.text = "ATK —"
		if def_label != null: def_label.text = "DEF —"
		if spd_label != null: spd_label.text = "SPD —"
		return
	if level_label != null: level_label.text = "Lv %d" % c.level
	if hp_label != null: hp_label.text = "HP %d/%d" % [c.hp, c.max_hp]
	# CharacterData has no MP field today — render a dash so the row reads
	# as "planned but unimplemented" rather than a fake zero. PRD #42 calls
	# out MP in the stats list; surfacing the row keeps the layout stable
	# once the resource gains the field.
	if mp_label != null: mp_label.text = "MP —"
	if atk_label != null: atk_label.text = "ATK %d" % c.attack
	if def_label != null: def_label.text = "DEF %d" % c.defense
	if spd_label != null: spd_label.text = "SPD %d" % int(round(c.speed))

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

func _make_skill_row(node: SkillNode, manager: SkillTreeManager) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "SkillRow_%s" % node.id
	var label := Label.new()
	label.name = "SkillRowLabel_%s" % node.id
	# Status suffix is the visually-distinct marker between locked and
	# unlocked nodes the acceptance criterion calls for. A future polish
	# pass can swap in icons / color tints, but the text contract is what
	# the tests pin.
	var status := "Unlocked" if node.unlocked else "Locked"
	label.text = "%s — %s" % [node.display_name, status]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if not node.unlocked:
		var btn := Button.new()
		btn.name = "UnlockButton_%s" % node.id
		btn.text = "Unlock (%d pt)" % node.cost
		btn.disabled = manager == null or not manager.can_unlock(node.id)
		var node_id := node.id
		btn.pressed.connect(func(): try_unlock_skill(node_id))
		row.add_child(btn)
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

func _on_settings_pressed() -> void:
	open_settings_submenu()

func _on_settings_back_pressed() -> void:
	close_settings_submenu()
