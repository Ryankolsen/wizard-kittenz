extends GutTest

# Slice 3 of PRD #210. QuickbarHUD view: 2×2 grid bound to a Quickbar.
# These tests pin the wiring: scene loads, four slot views are created
# with the cast_slot_N action mapping, fire-highlight pulses on
# controller.slot_fired, empty-slot tap emits empty_slot_pressed.

const QuickbarHUDScene := preload("res://scenes/quickbar_hud.tscn")
const SlotViewScript := preload("res://scripts/ui/quickbar_slot_view.gd")

class _StubController:
	signal slot_fired(slot: int)

class _StubPlayer:
	var data = null
	var _qb = null
	var _ctrl = null
	func get_quickbar():
		return _qb
	func get_quickbar_controller():
		return _ctrl

func _make_hud(player) -> QuickbarHUD:
	var hud: QuickbarHUD = QuickbarHUDScene.instantiate()
	add_child_autofree(hud)
	hud.bind_player(player)
	return hud

func _wizard_tree() -> SkillTree:
	return SkillTree.make_wizard_kitten_tree()

func test_slot_size_is_28():
	# PRD #384 / slice 2 (#386). SLOT_SIZE shrinks 32→28; computed 2×2 grid
	# becomes 60×60 (2*28 + 4 spacing).
	assert_eq(QuickbarHUD.SLOT_SIZE, 28.0)
	var hud: QuickbarHUD = QuickbarHUDScene.instantiate()
	add_child_autofree(hud)
	assert_eq(hud.size, Vector2(60, 60))

func test_slot_positions_use_32px_stride():
	# 28 (SLOT_SIZE) + 4 (SLOT_SPACING) = 32 stride between slot origins.
	var hud: QuickbarHUD = QuickbarHUDScene.instantiate()
	add_child_autofree(hud)
	assert_eq(hud.get_node("Slot1").position, Vector2(0, 0))
	assert_eq(hud.get_node("Slot2").position, Vector2(32, 0))
	assert_eq(hud.get_node("Slot3").position, Vector2(0, 32))
	assert_eq(hud.get_node("Slot4").position, Vector2(32, 32))
	assert_eq(hud.get_node("Slot1").size, Vector2(28, 28))

func test_quickbar_hud_scene_instantiates_four_slots():
	var hud: QuickbarHUD = QuickbarHUDScene.instantiate()
	add_child_autofree(hud)
	# Slots are created in _ready.
	for i in range(1, Quickbar.SLOT_COUNT + 1):
		var v = hud.get_node_or_null("Slot%d" % i)
		assert_not_null(v, "Slot%d must exist" % i)
		assert_true(v is QuickbarSlotView)
		assert_eq(v.slot_index, i)
		assert_eq(v.action_name, StringName("cast_slot_%d" % i))

func test_quickbar_hud_bind_player_refreshes_assigned_slots():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var hairball := tree.find("hairball_hex").spell
	qb.assign(1, hairball)
	var p := _StubPlayer.new()
	p._qb = qb
	p._ctrl = _StubController.new()
	var hud := _make_hud(p)
	# Force the polling refresh tick.
	hud._process(0.016)
	var slot1: QuickbarSlotView = hud.get_node("Slot1")
	# After refresh, slot1's internal state should reflect the assigned spell.
	assert_false(slot1._state.get("empty", true), "slot 1 should not be empty after assign")

func test_controller_slot_fired_triggers_fire_highlight():
	var p := _StubPlayer.new()
	p._qb = Quickbar.new()
	p._ctrl = _StubController.new()
	var hud := _make_hud(p)
	var slot1: QuickbarSlotView = hud.get_node("Slot1")
	assert_eq(slot1._fire_glow, 0.0, "starts unlit")
	p._ctrl.slot_fired.emit(1)
	assert_gt(slot1._fire_glow, 0.0, "fire highlight should pulse on slot_fired")

func test_empty_slot_press_emits_signal():
	var p := _StubPlayer.new()
	p._qb = Quickbar.new()
	p._ctrl = _StubController.new()
	var hud := _make_hud(p)
	hud._process(0.016)
	watch_signals(hud)
	var slot1: QuickbarSlotView = hud.get_node("Slot1")
	slot1.emit_signal("empty_slot_pressed", 1)
	assert_signal_emitted_with_parameters(hud, "empty_slot_pressed", [1])
