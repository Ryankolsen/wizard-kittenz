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

func test_touch_controls_quickbar_offset_box_is_60_by_60():
	# PRD #384 / slice 2 (#386). Slot shrink 32→28 cascades to the offset box
	# in touch_controls.tscn: 2*28 + 4 = 60 footprint.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var quickbar: Control = inst.get_node("QuickbarHUD")
	assert_eq(quickbar.offset_right - quickbar.offset_left, 60.0,
		"QuickbarHUD width box must be 60 (2*28 + 4)")
	assert_eq(quickbar.offset_bottom - quickbar.offset_top, 60.0,
		"QuickbarHUD height box must be 60 (2*28 + 4)")

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

func test_touch_controls_contains_vertical_potion_belt():
	# PRD #384 / slice 4 (#388). The mobile cluster owns its own PotionBeltHUD
	# in vertical orientation, sitting left of the QuickbarHUD magic grid.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var potion: Control = inst.get_node_or_null("PotionBeltHUD") as Control
	assert_not_null(potion, "TouchControls must instance a PotionBeltHUD child")
	assert_true(potion is PotionBeltHUD,
		"PotionBeltHUD child must be bound to the PotionBeltHUD script")
	assert_eq(potion.orientation, PotionBeltHUD.Orientation.VERTICAL,
		"mobile potion belt must be in vertical orientation")

func test_touch_potion_belt_sits_left_of_quickbar_top_aligned():
	# Content detail: the potion column's right edge must be at or left of the
	# QuickbarHUD's left edge (no overlap), and tops aligned within a small
	# tolerance so the column reads as one cluster with the magic grid.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var potion: Control = inst.get_node("PotionBeltHUD") as Control
	var quickbar: Control = inst.get_node("QuickbarHUD") as Control
	assert_true(potion.offset_right <= quickbar.offset_left,
		"potion column right edge must not overlap the magic grid's left edge")
	assert_almost_eq(potion.offset_top, quickbar.offset_top, 1.0,
		"potion column must top-align with the magic grid")

func test_apply_layout_right_hand_mirrors_potion_belt():
	# Mirroring keeps the potion column adjacent to the (now mirrored) magic
	# grid on the opposite side of the screen.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var potion: Control = inst.get_node("PotionBeltHUD") as Control
	var quickbar: Control = inst.get_node("QuickbarHUD") as Control
	var pot_w := potion.offset_right - potion.offset_left
	var qb_w := quickbar.offset_right - quickbar.offset_left
	inst.apply_layout("right_hand")
	# After mirror, potion sits to the RIGHT of the quickbar.
	assert_true(potion.offset_left >= quickbar.offset_right,
		"after right-hand mirror, potion column must sit to the right of the magic grid")
	# Widths preserved.
	assert_almost_eq(potion.offset_right - potion.offset_left, pot_w, 0.01,
		"mirror must preserve potion column width")
	assert_almost_eq(quickbar.offset_right - quickbar.offset_left, qb_w, 0.01,
		"mirror must preserve quickbar width")

func test_hud_hides_potion_belt_on_touch_platform():
	# PRD #384 / slice 4 (#388). On touch, the cluster lives in TouchControls;
	# the HUD-layer PotionBeltHUD must hide so we don't double-render at the
	# old desktop position. Mirrors the existing QuickbarHUD hide path.
	if not TouchControls.is_touch_platform():
		# Reuse the same gate the HUD hide branch checks. On desktop the HUD
		# layer keeps the PotionBeltHUD visible; nothing to verify here.
		pending("hud potion-belt hide is touch-only")
		return
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var potion = hud.get_node_or_null("PotionBeltHUD") as Control
	assert_not_null(potion, "hud.tscn must still ship a PotionBeltHUD for desktop")
	assert_false(potion.visible,
		"on touch platforms, HUD-layer PotionBeltHUD must be hidden")

func test_cluster_top_clears_minimap_bottom():
	# PRD #384 / slice 5 (#389). The minimap (HUD layer) bottom edge is y=122.
	# The mobile cluster sits on a higher CanvasLayer, so any overlap draws
	# magic buttons on top of the minimap. The cluster must clear that edge
	# by at least 4px.
	const MINIMAP_BOTTOM := 122.0
	const MIN_GAP := 4.0
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var quickbar: Control = inst.get_node("QuickbarHUD") as Control
	assert_true(quickbar.offset_top >= MINIMAP_BOTTOM + MIN_GAP,
		"magic grid top edge must clear minimap bottom (122) by >= 4px")

func test_potion_column_top_clears_minimap_bottom():
	# Same contract for the potion column — it top-aligns with the magic grid,
	# so it must clear the minimap by the same threshold.
	const MINIMAP_BOTTOM := 122.0
	const MIN_GAP := 4.0
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var potion: Control = inst.get_node("PotionBeltHUD") as Control
	assert_true(potion.offset_top >= MINIMAP_BOTTOM + MIN_GAP,
		"potion column top edge must clear minimap bottom (122) by >= 4px")

func test_cluster_does_not_overlap_attack_button_left_hand():
	# Edge case: pushing the cluster down must not collide with the AttackButton.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	var quickbar: Control = inst.get_node("QuickbarHUD") as Control
	var potion: Control = inst.get_node("PotionBeltHUD") as Control
	var attack: Control = inst.get_node("AttackButton") as Control
	assert_true(quickbar.offset_bottom <= attack.offset_top,
		"magic grid bottom edge must not overlap the attack button (left-hand layout)")
	assert_true(potion.offset_bottom <= attack.offset_top,
		"potion column bottom edge must not overlap the attack button (left-hand layout)")

func test_cluster_does_not_overlap_attack_button_right_hand():
	# Mirroring swaps X only; the vertical clearance must still hold.
	var inst = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(inst)
	inst.apply_layout("right_hand")
	var quickbar: Control = inst.get_node("QuickbarHUD") as Control
	var potion: Control = inst.get_node("PotionBeltHUD") as Control
	var attack: Control = inst.get_node("AttackButton") as Control
	assert_true(quickbar.offset_bottom <= attack.offset_top,
		"magic grid bottom edge must not overlap the attack button (right-hand layout)")
	assert_true(potion.offset_bottom <= attack.offset_top,
		"potion column bottom edge must not overlap the attack button (right-hand layout)")

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
