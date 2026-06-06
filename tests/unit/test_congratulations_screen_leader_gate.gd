extends GutTest

# PRD #348 / issue #350 — leader-gate the CongratulationsScreen's Next Floor
# affordance. The screen's `populate(...)` grows an `is_leader` flag:
#   - leader (or solo, treated as leader): the existing "Next Floor" button
#     stays visible and active and emits `next_floor_pressed` on press.
#   - non-leader: the button is replaced by a passive status label reading
#     "Waiting for the party leader to choose the next floor…" and there
#     is no path to emit `next_floor_pressed`.
# "Update Character" and "Save & Exit" remain active for both roles; the
# floor summary + headline still render. Pure receive-side UI gate — the
# wire-side leader gate already lives on the OP_ADVANCE_FLOOR path.

const SCENE_PATH := "res://scenes/congratulations_screen.tscn"
const WAITING_TEXT := "Waiting for the party leader to choose the next floor…"

func _instantiate() -> CongratulationsScreen:
	var scene: CongratulationsScreen = load(SCENE_PATH).instantiate()
	add_child_autofree(scene)
	return scene

func _build_summary() -> FloorRunSummary:
	return FloorRunSummary.new(2, 11, 120, 45)

# 1. Core wiring — leader path keeps the button active and pressable.
func test_leader_next_floor_button_visible_active_and_emits():
	var s := _instantiate()
	watch_signals(s)
	s.populate(_build_summary(), "Headline", true)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/NextFloor")
	assert_true(btn.visible, "leader next-floor button should be visible")
	assert_false(btn.disabled, "leader next-floor button should not be disabled")
	btn.pressed.emit()
	assert_signal_emitted(s, "next_floor_pressed")

# 2a. Non-leader path hides the button and shows the waiting label.
func test_non_leader_next_floor_replaced_with_waiting_label():
	var s := _instantiate()
	s.populate(_build_summary(), "Headline", false)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/NextFloor")
	assert_false(btn.visible, "non-leader next-floor button should be hidden")
	var status: Label = s.get_node_or_null("Backdrop/Center/Panel/VBox/ButtonRow/WaitingLabel")
	assert_not_null(status, "non-leader screen should expose a waiting status label")
	assert_true(status.visible, "waiting status should be visible for non-leader")
	assert_eq(status.text, WAITING_TEXT)

# 2b. Headline + summary labels render in both leader states.
func test_headline_and_summary_render_for_both_states():
	for is_leader in [true, false]:
		var s := _instantiate()
		s.populate(FloorRunSummary.new(7, 33, 410, 99), "Boss down!", is_leader)
		var headline: Label = s.get_node("Backdrop/Center/Panel/VBox/Headline")
		assert_eq(headline.text, "Boss down!",
			"headline must render for is_leader=%s" % [is_leader])
		var floor_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/FloorLabel")
		var enemies_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/EnemiesLabel")
		var xp_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/XPLabel")
		var gold_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/GoldLabel")
		assert_true(floor_lbl.text.find("7") != -1)
		assert_true(enemies_lbl.text.find("33") != -1)
		assert_true(xp_lbl.text.find("410") != -1)
		assert_true(gold_lbl.text.find("99") != -1)

# 3a. Non-leader can't emit next_floor_pressed — the active affordance
# is absent (hidden + disabled), so any stray bubble of the press event
# is dropped at the source.
func test_non_leader_cannot_emit_next_floor_pressed():
	var s := _instantiate()
	watch_signals(s)
	s.populate(_build_summary(), "Headline", false)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/NextFloor")
	assert_true(btn.disabled or not btn.visible,
		"non-leader next-floor button must be disabled or hidden")
	# Disabled buttons swallow pressed.emit() in Godot, but pin the no-emit
	# contract directly so a future Button refactor can't silently regress it.
	btn.pressed.emit()
	assert_signal_emit_count(s, "next_floor_pressed", 0)

# 3b. Update Character / Save & Exit remain active for both states.
func test_other_buttons_active_and_emit_in_both_states():
	for is_leader in [true, false]:
		var s := _instantiate()
		watch_signals(s)
		s.populate(_build_summary(), "Headline", is_leader)
		var update_btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter")
		var exit_btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit")
		assert_true(update_btn.visible and not update_btn.disabled,
			"update button must stay active for is_leader=%s" % [is_leader])
		assert_true(exit_btn.visible and not exit_btn.disabled,
			"exit button must stay active for is_leader=%s" % [is_leader])
		update_btn.pressed.emit()
		exit_btn.pressed.emit()
		assert_signal_emitted(s, "update_character_pressed")
		assert_signal_emitted(s, "save_and_exit_pressed")
