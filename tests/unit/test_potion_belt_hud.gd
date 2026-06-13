extends GutTest

# Slice 8 of PRD #358. PotionBeltHUD view: 1×3 strip bound to a PotionBelt +
# ConsumableInventory. Pins the wiring: scene loads, three slot views are
# created with the use_potion_N action mapping, the input-action -> slot-index
# helper resolves correctly, and try_use_slot routes into PotionBelt.use_slot
# (which itself enforces empty/0-count/cooldown gates — these are not a HUD
# concern).

const PotionBeltHUDScene := preload("res://scenes/potion_belt_hud.tscn")
const PotionBeltHUDScript := preload("res://scripts/ui/potion_belt_hud.gd")
const SlotViewScript := preload("res://scripts/ui/potion_belt_slot_view.gd")

class _StubPlayer:
	var data = null
	var _belt = null
	var _inv = null
	func get_potion_belt():
		return _belt
	func get_consumable_inventory():
		return _inv

func _make_hud(belt, inventory, caster = null) -> PotionBeltHUD:
	var hud: PotionBeltHUD = PotionBeltHUDScene.instantiate()
	add_child_autofree(hud)
	hud.bind(belt, inventory, caster)
	return hud

func test_scene_instantiates_two_slot_views():
	# PRD #384 / slice 1 (#385). Exactly two slot views; no Slot3 child.
	var hud: PotionBeltHUD = PotionBeltHUDScene.instantiate()
	add_child_autofree(hud)
	assert_eq(PotionBelt.SLOT_COUNT, 2)
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		var v = hud.get_node_or_null("Slot%d" % i)
		assert_not_null(v, "Slot%d must exist" % i)
		assert_true(v is PotionBeltSlotView)
		assert_eq(v.slot_index, i)
		assert_eq(v.action_name, StringName("use_potion_%d" % i))
	assert_null(hud.get_node_or_null("Slot3"), "Slot3 must not exist after 3→2 reduction")
	assert_eq(hud.get_node("Slot2").action_name, StringName("use_potion_2"))

func test_action_to_slot_helper_maps_use_potion_N_to_slot_N():
	# Pure mapping helper, parallel to the cast_slot_N pattern in
	# QuickbarController. The HUD's _poll_inputs leans on this; exposing it as
	# a static keeps the routing logic unit-testable without driving Input.
	assert_eq(PotionBeltHUDScript.slot_for_action(&"use_potion_1"), 1)
	assert_eq(PotionBeltHUDScript.slot_for_action(&"use_potion_2"), 2)
	assert_eq(PotionBeltHUDScript.slot_for_action(&"use_potion_3"), 0, "use_potion_3 removed in #385")
	assert_eq(PotionBeltHUDScript.slot_for_action(&"use_potion_4"), 0, "unknown returns 0")
	assert_eq(PotionBeltHUDScript.slot_for_action(&"cast_slot_1"), 0, "non-potion action returns 0")

func test_try_use_slot_routes_into_belt_use_slot_and_emits():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	belt.assign(2, "health_potion")
	inv.add("health_potion", 1)
	var caster := CharacterData.new()
	caster.max_hp = 100
	caster.hp = 50
	var hud := _make_hud(belt, inv, caster)
	watch_signals(hud)
	var ok := hud.try_use_slot(2)
	assert_true(ok, "use_slot should succeed when slot is loaded and stocked")
	assert_eq(inv.count_of("health_potion"), 0, "potion should be consumed")
	assert_true(belt.is_on_cooldown(), "belt cooldown should arm")
	assert_signal_emitted_with_parameters(hud, "slot_used", [2])

func test_try_use_slot_returns_false_when_empty_slot_no_consume():
	# Mirrors PotionBelt's no-mutation-on-fail contract — the HUD does not
	# re-validate, it just trusts the bool. Empty slot tap = harmless.
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	var hud := _make_hud(belt, inv, null)
	watch_signals(hud)
	var ok := hud.try_use_slot(1)
	assert_false(ok)
	assert_signal_not_emitted(hud, "slot_used")

func test_try_use_slot_returns_false_when_count_zero():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	var inv := ConsumableInventory.new()
	# count of 0 — assignment alone isn't enough
	var hud := _make_hud(belt, inv, null)
	watch_signals(hud)
	var ok := hud.try_use_slot(1)
	assert_false(ok, "zero count blocks the fire")
	assert_signal_not_emitted(hud, "slot_used")

func test_try_use_slot_returns_false_during_cooldown():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	belt.assign(2, "mana_potion")
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 5)
	inv.add("mana_potion", 5)
	var caster := CharacterData.new()
	caster.max_hp = 100
	caster.hp = 50
	caster.max_mp = 100
	caster.magic_points = 50
	var hud := _make_hud(belt, inv, caster)
	assert_true(hud.try_use_slot(1), "first fire arms cooldown")
	watch_signals(hud)
	var ok := hud.try_use_slot(2)
	assert_false(ok, "shared cooldown blocks second slot")
	assert_signal_not_emitted(hud, "slot_used")
	assert_eq(inv.count_of("mana_potion"), 5, "no consume on blocked use")

func test_refresh_renders_per_slot_state_from_potion_slot_state():
	# Per-slot render values come from PotionSlotState.derive — already
	# unit-tested in test_potion_slot_state. This test only pins that the HUD
	# actually calls into derive (slot state ends up non-empty after assign).
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 3)
	var hud := _make_hud(belt, inv, null)
	hud._process(0.0)
	var slot1: PotionBeltSlotView = hud.get_node("Slot1")
	assert_false(slot1._state.get("empty", true), "slot 1 should render non-empty after assign")
	assert_eq(int(slot1._state.get("count", 0)), 3, "count should reflect inventory")

func test_bind_player_reads_belt_and_inventory_from_player_methods():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 2)
	var p := _StubPlayer.new()
	p._belt = belt
	p._inv = inv
	var hud: PotionBeltHUD = PotionBeltHUDScene.instantiate()
	add_child_autofree(hud)
	hud.bind_player(p)
	hud._process(0.0)
	var slot1: PotionBeltSlotView = hud.get_node("Slot1")
	assert_false(slot1._state.get("empty", true))

func test_process_ticks_belt_cooldown_each_frame():
	# HUD owns the per-frame belt.tick(delta) call (per slice-4 commit notes).
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 1)
	var caster := CharacterData.new()
	caster.max_hp = 100
	caster.hp = 50
	var hud := _make_hud(belt, inv, caster)
	hud.try_use_slot(1)
	var before := belt.cooldown_remaining()
	hud._process(1.0)
	assert_lt(belt.cooldown_remaining(), before, "tick should drain cooldown")
