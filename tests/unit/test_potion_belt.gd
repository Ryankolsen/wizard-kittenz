extends GutTest

# PRD #358 / slice 4 — PotionBelt data class. Pure-data 3-slot belt referencing
# potion ids (not PotionDefinitions), with shared cooldown gating use_slot.

func test_slot_count_is_two():
	# PRD #384 / slice 1 (#385). Belt is exactly two slots end-to-end.
	assert_eq(PotionBelt.SLOT_COUNT, 2)
	var belt := PotionBelt.new()
	assert_eq(belt.get_slot(1), "")
	assert_eq(belt.get_slot(2), "")
	# Slot 3 is out of range now — get returns "" and assign/use are safe no-ops.
	assert_eq(belt.get_slot(3), "")
	belt.assign(3, "health_potion")
	assert_eq(belt.get_slot(3), "")
	assert_false(belt.use_slot(3, _caster(), ConsumableInventory.new()))

func test_assign_places_potion_in_slot():
	var belt := PotionBelt.new()
	watch_signals(belt)
	belt.assign(1, "health_potion")
	assert_eq(belt.get_slot(1), "health_potion")
	assert_signal_emitted_with_parameters(belt, "slot_changed", [1])

func test_assign_swap_when_potion_already_in_other_slot():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	belt.assign(2, "mana_potion")
	belt.assign(2, "health_potion")
	assert_eq(belt.get_slot(1), "mana_potion")
	assert_eq(belt.get_slot(2), "health_potion")

func test_assign_same_slot_noop():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	watch_signals(belt)
	belt.assign(1, "health_potion")
	assert_signal_not_emitted(belt, "slot_changed")

func test_unassign_clears_slot_and_emits():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	watch_signals(belt)
	belt.unassign(1)
	assert_eq(belt.get_slot(1), "")
	assert_signal_emitted_with_parameters(belt, "slot_changed", [1])

func _caster() -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")
	c.hp = 1
	c.magic_points = 0
	return c

func test_use_slot_consumes_inventory_emits_used():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 3)
	belt.assign(1, "health_potion")
	watch_signals(belt)
	var caster := _caster()
	assert_true(belt.use_slot(1, caster, inv))
	assert_eq(inv.count_of("health_potion"), 2)
	assert_signal_emitted_with_parameters(belt, "slot_used", [1])

func test_use_slot_empty_returns_false():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	watch_signals(belt)
	assert_false(belt.use_slot(1, _caster(), inv))
	assert_signal_not_emitted(belt, "slot_used")

func test_use_slot_zero_count_returns_false():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	belt.assign(1, "health_potion")
	watch_signals(belt)
	assert_false(belt.use_slot(1, _caster(), inv))
	assert_signal_not_emitted(belt, "slot_used")
	assert_eq(inv.count_of("health_potion"), 0)

func test_shared_cooldown_blocks_second_use():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 2)
	inv.add("mana_potion", 2)
	belt.assign(1, "health_potion")
	belt.assign(2, "mana_potion")
	var caster := _caster()
	assert_true(belt.use_slot(1, caster, inv))
	assert_false(belt.use_slot(2, caster, inv))
	# Mana potion was NOT consumed because the belt is on cooldown.
	assert_eq(inv.count_of("mana_potion"), 2)

func test_tick_past_cooldown_reenables_use():
	var belt := PotionBelt.new()
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 2)
	belt.assign(1, "health_potion")
	var caster := _caster()
	assert_true(belt.use_slot(1, caster, inv))
	belt.tick(PotionBelt.COOLDOWN_SECONDS + 0.1)
	assert_true(belt.use_slot(1, caster, inv))
	assert_eq(inv.count_of("health_potion"), 0)

func test_deserialize_drops_extra_slot_entries():
	# PRD #384 / slice 1 (#385). A save written before the 3→2 reduction may
	# carry three slot entries; deserialize must drop the third silently.
	var belt := PotionBelt.new()
	belt.deserialize({"slots": ["health_potion", "mana_potion", "shield_potion"]})
	assert_eq(belt.get_slot(1), "health_potion")
	assert_eq(belt.get_slot(2), "mana_potion")
	assert_eq(belt.get_slot(3), "")
