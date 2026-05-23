extends GutTest

# Issue #197: InteractableNPC base — proximity gate, attack-press → bubble
# mount, option-confirm → _handle_effect dispatch. Bartender is the first
# subclass; this file pins the base behavior with a tiny test subclass so
# regressions in the reusable layer are caught without depending on the
# bartender's specific menu.


class _RecordingNPC extends InteractableNPC:
	var last_effect_id: String = ""
	var handle_calls: int = 0

	func _build_option_list() -> NPCOptionList:
		return NPCOptionList.make([
			NPCOption.make("First", "do_first"),
			NPCOption.make("Second", "do_second"),
		] as Array[NPCOption])

	func _handle_effect(effect_id: String) -> void:
		last_effect_id = effect_id
		handle_calls += 1


func _make_npc() -> _RecordingNPC:
	var npc := _RecordingNPC.new()
	add_child_autofree(npc)
	return npc


func test_base_mounts_bubble_with_subclass_options():
	var npc := _make_npc()
	npc._on_player_entered_range()
	npc._on_attack_pressed()
	var bubble := npc.get_bubble()
	assert_not_null(bubble, "bubble mounted after in-range attack press")
	assert_eq(bubble._list.size(), 2, "bubble shows the two subclass options")
	assert_eq(bubble._list.get(0).label, "First")


func test_base_dispatches_effect_id_to_subclass():
	# Core wiring: confirming an option lands the matching effect_id on the
	# subclass's _handle_effect hook.
	var npc := _make_npc()
	npc._on_player_entered_range()
	npc._on_attack_pressed()
	var bubble := npc.get_bubble()
	bubble.confirm()  # cursor on row 0 (First) -> "do_first"
	assert_eq(npc.last_effect_id, "do_first",
		"subclass receives the confirmed option's effect_id")
	assert_eq(npc.handle_calls, 1, "_handle_effect called exactly once")


func test_base_dispatches_second_option_when_navigated():
	var npc := _make_npc()
	npc._on_player_entered_range()
	npc._on_attack_pressed()
	var bubble := npc.get_bubble()
	bubble.move_next()
	bubble.confirm()
	assert_eq(npc.last_effect_id, "do_second",
		"navigating to row 1 then confirming dispatches that row's effect_id")


func test_base_does_not_open_bubble_when_out_of_range():
	var npc := _make_npc()
	# No _on_player_entered_range call.
	npc._on_attack_pressed()
	assert_null(npc.get_bubble(),
		"no bubble when player has never entered range")
	assert_eq(npc.handle_calls, 0, "_handle_effect not called")


func test_base_closes_bubble_on_proximity_exit():
	var npc := _make_npc()
	npc._on_player_entered_range()
	npc._on_attack_pressed()
	assert_not_null(npc.get_bubble())
	npc._on_player_exited_range()
	assert_null(npc.get_bubble(),
		"bubble cleared when player exits proximity")


func test_base_open_menu_reopens_after_close():
	# Public open_menu() lets external callers (BarRoom on shop close)
	# reopen the menu without faking input.
	var npc := _make_npc()
	npc._on_player_entered_range()
	npc.open_menu()
	var first := npc.get_bubble()
	assert_not_null(first)
	first.move_next()
	first.confirm()  # row 1 -> "do_second"; base doesn't auto-close, but the
	# test subclass doesn't close either, so bubble stays open. Verify
	# open_menu is idempotent (does NOT stack a second bubble on top).
	npc.open_menu()
	assert_eq(npc.get_bubble(), first,
		"open_menu while bubble is already up does not replace it")


func test_base_open_menu_noop_when_out_of_range():
	var npc := _make_npc()
	# Never entered range.
	npc.open_menu()
	assert_null(npc.get_bubble(),
		"open_menu is a no-op when player is out of range")
