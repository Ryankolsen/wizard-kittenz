extends GutTest

const _QuickbarController = preload("res://scripts/character/quickbar_controller.gd")

# Slice 2 of PRD #210: QuickbarController dispatches cast_slot_N input into
# Quickbar.fire_slot. The routing logic is exercised via try_fire_slot()
# (a public seam) so tests don't lean on Input.action_press, whose
# is_action_just_pressed flag persists across calls within a single
# synchronous test body. One smoke test drives the Input layer end-to-end.


class _StubQuickbar:
	var calls: Array = []
	var return_value: bool = true
	func fire_slot(n: int, caster = null) -> bool:
		calls.append([n, caster])
		return return_value


func _make_controller(stub) -> _QuickbarController:
	var c := _QuickbarController.new()
	c.quickbar = stub
	add_child_autofree(c)
	return c


func test_try_fire_slot_dispatches_slot_number_into_quickbar():
	var stub := _StubQuickbar.new()
	var c := _make_controller(stub)
	c.try_fire_slot(1)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0][0], 1)


func test_try_fire_slot_routes_each_of_the_four_slots():
	for i in range(1, 5):
		var stub := _StubQuickbar.new()
		var c := _make_controller(stub)
		c.try_fire_slot(i)
		assert_eq(stub.calls.size(), 1, "slot %d should fire once" % i)
		assert_eq(stub.calls[0][0], i, "slot %d should dispatch slot %d" % [i, i])


func test_caster_is_passed_through_to_quickbar():
	var stub := _StubQuickbar.new()
	var c := _make_controller(stub)
	var fake_caster := RefCounted.new()
	c.caster = fake_caster
	c.try_fire_slot(2)
	assert_eq(stub.calls[0][1], fake_caster)


func test_fire_slot_returning_false_emits_no_slot_fired_signal():
	var stub := _StubQuickbar.new()
	stub.return_value = false
	var c := _make_controller(stub)
	watch_signals(c)
	c.try_fire_slot(1)
	assert_signal_not_emitted(c, "slot_fired")


func test_fire_slot_returning_true_emits_slot_fired_with_slot_number():
	var stub := _StubQuickbar.new()
	stub.return_value = true
	var c := _make_controller(stub)
	watch_signals(c)
	c.try_fire_slot(3)
	assert_signal_emitted_with_parameters(c, "slot_fired", [3])


func test_no_quickbar_assigned_is_safe_noop():
	var c := _QuickbarController.new()
	add_child_autofree(c)
	watch_signals(c)
	assert_false(c.try_fire_slot(1))
	assert_signal_not_emitted(c, "slot_fired")


# Smoke test: _poll_inputs actually consumes the cast_slot_1 InputMap action.
# Kept as a single test so the just_pressed flag doesn't leak across multiple
# action presses within the same frame.
func test_poll_inputs_dispatches_cast_slot_1_press():
	var stub := _StubQuickbar.new()
	var c := _make_controller(stub)
	Input.action_press("cast_slot_1")
	c._poll_inputs()
	Input.action_release("cast_slot_1")
	assert_eq(stub.calls.size(), 1, "press of cast_slot_1 should fire one slot")
	assert_eq(stub.calls[0][0], 1, "cast_slot_1 maps to slot 1")
