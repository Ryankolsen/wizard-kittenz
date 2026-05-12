extends GutTest

# Regression guard for the Android-keyboard input bug (#25).
#
# The input actions in project.godot were originally authored with
# `keycode: 0` and only `physical_keycode` set. Android's keyboard
# input pipeline does not reliably populate physical_keycode (and
# when it does, the value can be a Linux scancode rather than a
# Godot KEY_*), so action matching was failing or matching the
# wrong action — symptom: WASD unresponsive, arrow keys remapped
# to scrambled axes on the Android emulator.
#
# Fix: every InputEventKey on every gameplay action now has BOTH
# `keycode` (logical, cross-platform) and `physical_keycode` set
# to the same Godot KEY_* value. These tests fail if a future
# project.godot edit drops `keycode` back to 0 on any event.
#
# We assert on InputMap (not by parsing project.godot) so the test
# exercises what the engine actually loads — if the file format
# ever changes shape, the matching behaviour is what matters here.

const GAMEPLAY_ACTIONS := [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"attack",
	"cast_spell",
]

# Expected (keycode, physical_keycode) pairs per action. The values
# match Godot's KEY_* constants — see project.godot. Pinning both
# fields prevents a regression where one is set and the other isn't,
# which is the exact failure mode #25 caught.
const EXPECTED_KEYS := {
	"move_left":  [[65, 65], [4194319, 4194319]],          # A, Left
	"move_right": [[68, 68], [4194321, 4194321]],          # D, Right
	"move_up":    [[87, 87], [4194320, 4194320]],          # W, Up
	"move_down":  [[83, 83], [4194322, 4194322]],          # S, Down
	"attack":     [[32, 32], [74, 74]],                    # Space, J
	"cast_spell": [[81, 81], [70, 70]],                    # Q, F
}

func test_all_gameplay_actions_registered():
	for action in GAMEPLAY_ACTIONS:
		assert_true(InputMap.has_action(action),
			"InputMap must define gameplay action '%s'" % action)

func test_every_action_event_has_keycode_set():
	# This is the actual #25 regression: a keycode of 0 on Android
	# means the action never fires from a hardware-keyboard event.
	for action in GAMEPLAY_ACTIONS:
		var events: Array = InputMap.action_get_events(action)
		assert_gt(events.size(), 0,
			"Action '%s' must have at least one InputEvent" % action)
		for event in events:
			if event is InputEventKey:
				var key_event: InputEventKey = event
				assert_ne(key_event.keycode, 0,
					("Action '%s' has an InputEventKey with keycode=0; "
					+ "Android keyboard input will not match. Set both "
					+ "keycode and physical_keycode in project.godot.") % action)

func test_every_action_event_has_physical_keycode_set():
	# Desktop matching still relies on physical_keycode for layout-
	# independent input. Both must be populated.
	for action in GAMEPLAY_ACTIONS:
		var events: Array = InputMap.action_get_events(action)
		for event in events:
			if event is InputEventKey:
				var key_event: InputEventKey = event
				assert_ne(key_event.physical_keycode, 0,
					"Action '%s' has an InputEventKey with physical_keycode=0" % action)

func test_action_keycodes_match_expected_layout():
	# Pins the full WASD + arrows + Space/J + Q/F binding so a future
	# project.godot edit that silently scrambles assignments fails
	# loudly. (Scrambled arrow keys was a #25 symptom.)
	for action in EXPECTED_KEYS.keys():
		var expected: Array = EXPECTED_KEYS[action]
		var events: Array = InputMap.action_get_events(action)
		var key_events: Array = []
		for event in events:
			if event is InputEventKey:
				key_events.append(event)
		assert_eq(key_events.size(), expected.size(),
			"Action '%s' should have %d key bindings, got %d"
				% [action, expected.size(), key_events.size()])
		for i in range(min(key_events.size(), expected.size())):
			var key_event: InputEventKey = key_events[i]
			var expected_pair: Array = expected[i]
			assert_eq(key_event.keycode, expected_pair[0],
				"Action '%s' event #%d keycode mismatch" % [action, i])
			assert_eq(key_event.physical_keycode, expected_pair[1],
				"Action '%s' event #%d physical_keycode mismatch" % [action, i])
