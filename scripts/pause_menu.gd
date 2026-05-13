class_name PauseMenu
extends CanvasLayer

# Pause overlay (PRD #42, walking skeleton in #44, Character submenu in
# #47). Owns its own visibility + the get_tree().paused flag in solo
# mode, plus a root-menu / Character-submenu swap inside the existing
# CenterContainer.
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
func open_character_submenu() -> void:
	visible = true
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = false
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = true
	_refresh_character_stats()

func close_character_submenu() -> void:
	_show_main_menu()

func _show_main_menu() -> void:
	var main := find_child("MainMenu", true, false) as Control
	if main != null:
		main.visible = true
	var submenu := find_child("CharacterSubmenu", true, false) as Control
	if submenu != null:
		submenu.visible = false

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

func _on_resume_pressed() -> void:
	close()

func _on_character_pressed() -> void:
	open_character_submenu()

func _on_back_pressed() -> void:
	close_character_submenu()
