class_name PauseMenu
extends CanvasLayer

# Walking skeleton for the pause overlay (PRD #42, walking-skeleton issue
# #44). Owns nothing but its own visibility + the get_tree().paused flag
# in solo mode. Submenus (#47–#50) and quit-dungeon save/resume (#45,
# #46) land in follow-up tasks — this scene just needs to open, close,
# and branch correctly between solo and multiplayer.
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

func open() -> void:
	visible = true
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

func _on_resume_pressed() -> void:
	close()
