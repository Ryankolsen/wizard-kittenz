extends GutTest

# Tests for the TouchControls platform-gate added for #25. The overlay
# must hide on desktop (test rigs, dev machines) so screenshots and
# manual play aren't polluted by an unreachable joystick, and must show
# on mobile so the game is actually playable.

func test_should_show_returns_true_when_forced():
	# force_visible is a test/dev escape hatch — lets us screenshot or
	# manually verify the overlay on desktop without flipping platform
	# features.
	assert_true(TouchControls.should_show(true),
		"force_visible=true should always show the overlay")

func test_should_show_matches_platform_when_not_forced():
	# On the desktop test rig OS.has_feature("mobile") is false, so the
	# overlay defaults hidden. On Android, OS.has_feature("mobile")
	# returns true and the overlay shows. We don't pin the value here
	# because that's platform-dependent — just that the function reads
	# from is_touch_platform.
	assert_eq(TouchControls.should_show(false), TouchControls.is_touch_platform(),
		"unforced visibility must match is_touch_platform")

func test_is_touch_platform_returns_bool():
	# Smoke: the helper exists and returns a typed bool.
	var result: bool = TouchControls.is_touch_platform()
	assert_true(typeof(result) == TYPE_BOOL,
		"is_touch_platform must return a bool")

func test_touch_controls_scene_can_load():
	# Confirms the .tscn parses and instances cleanly. Catches a broken
	# resource path or script binding before main.tscn fails to load.
	var scene := load("res://scenes/touch_controls.tscn")
	assert_not_null(scene, "touch_controls.tscn must be loadable")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "touch_controls.tscn must instantiate")
	assert_true(inst is CanvasLayer, "root node should be a CanvasLayer")
	# Confirm the joystick child is present and bound to the right script.
	var joystick: Node = inst.get_node_or_null("Joystick")
	assert_not_null(joystick, "Joystick child must exist in the scene")
	assert_true(joystick is VirtualJoystick,
		"Joystick child must be bound to the VirtualJoystick script")
	# Confirm both action buttons are present and bound to the right actions.
	var attack: Node = inst.get_node_or_null("AttackButton")
	assert_not_null(attack, "AttackButton must exist in the scene")
	assert_true(attack is TouchActionButton)
	assert_eq(attack.action_name, &"attack",
		"AttackButton must be wired to the 'attack' InputMap action")
	# Slice 3 of PRD #210: legacy CastButton replaced by the QuickbarHUD
	# 2×2 grid (4 slots, each emitting cast_slot_N InputMap actions).
	assert_null(inst.get_node_or_null("CastButton"),
		"slice 3: CastButton must be removed (replaced by QuickbarHUD)")
	var quickbar: Node = inst.get_node_or_null("QuickbarHUD")
	assert_not_null(quickbar, "QuickbarHUD must be present in touch_controls.tscn")
	assert_true(quickbar is QuickbarHUD)
	inst.free()

func test_set_menu_open_true_hides_overlay():
	# While the pause menu is open the overlay must hide — its QuickbarHUD
	# slots share the menu's CanvasLayer and would otherwise intercept taps
	# on the Stats-tab "+" buttons.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	inst.force_visible = true
	add_child_autofree(inst)
	inst.set_menu_open(true)
	assert_false(inst.visible, "overlay must hide while the menu is open")

func test_set_menu_open_false_restores_platform_default():
	# Closing the menu returns the overlay to its platform-gated default
	# (here force_visible=true) rather than leaving it stuck hidden.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	inst.force_visible = true
	add_child_autofree(inst)
	inst.set_menu_open(true)
	inst.set_menu_open(false)
	assert_true(inst.visible, "overlay must return to its default on menu close")

func test_ready_registers_pause_hideable_group():
	# The PauseMenu finds the overlay via this group to hide it on open.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	assert_true(inst.is_in_group("touch_controls"),
		"TouchControls must join the 'touch_controls' group so the pause menu can hide it")

func test_main_scene_includes_touch_controls():
	# Regression guard: the wire-up into main.tscn is the only thing
	# that makes the controls actually visible in-game. If a future edit
	# strips the node, the game is back to keyboard-only on Android.
	var scene := load("res://scenes/main.tscn")
	assert_not_null(scene)
	var inst: Node = scene.instantiate()
	assert_not_null(inst.get_node_or_null("TouchControls"),
		"main.tscn must contain a TouchControls node")
	inst.free()
