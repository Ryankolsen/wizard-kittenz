extends GutTest

# Slice 1 (issue #359). ConsumableInventory tracks {potion_id: count} with
# add/consume/count_of, 99-stack cap, and save/load round-trip. Separate from
# gear-only ItemInventory because potions are typed by string id, not by slot.

func test_add_increases_count():
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 3)
	assert_eq(inv.count_of("health_potion"), 3)

func test_consume_decreases_count_and_returns_true():
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 3)
	assert_true(inv.consume("health_potion"))
	assert_eq(inv.count_of("health_potion"), 2)

func test_consume_on_empty_returns_false_and_no_mutation():
	var inv := ConsumableInventory.new()
	assert_false(inv.consume("health_potion"))
	assert_eq(inv.count_of("health_potion"), 0)

func test_add_clamps_at_99_stack_cap():
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 80)
	inv.add("health_potion", 50)
	assert_eq(inv.count_of("health_potion"), 99)

func test_serialize_deserialize_round_trip_preserves_counts():
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 5)
	inv.add("mana_potion", 12)
	var data := inv.serialize()
	var rebuilt := ConsumableInventory.new()
	rebuilt.deserialize(data)
	assert_eq(rebuilt.count_of("health_potion"), 5)
	assert_eq(rebuilt.count_of("mana_potion"), 12)
