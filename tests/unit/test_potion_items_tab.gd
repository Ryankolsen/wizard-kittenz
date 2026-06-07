extends GutTest

# Slice 9 of PRD #358 (issue #366). Items tab in the pause menu lists owned
# potions with their counts; each row gets three slot-toggle buttons that
# route through PotionBelt.assign / unassign. Pure helpers on the pause menu
# script are unit-tested here — the full panel render is covered by the QA
# slice (#368), per the issue note.

const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

func test_slot_holds_potion_true_only_when_slot_holds_that_id():
	var belt := PotionBelt.new()
	belt.assign(2, "health_potion")
	assert_true(PauseMenuScript._slot_holds_potion(belt, 2, "health_potion"),
		"slot 2 holds health_potion → true")
	assert_false(PauseMenuScript._slot_holds_potion(belt, 2, "mana_potion"),
		"slot 2 does not hold mana_potion → false")
	assert_false(PauseMenuScript._slot_holds_potion(belt, 1, "health_potion"),
		"slot 1 is empty → false")

func test_slot_holds_potion_null_belt_returns_false():
	assert_false(PauseMenuScript._slot_holds_potion(null, 1, "health_potion"))

func test_press_on_empty_slot_assigns():
	var belt := PotionBelt.new()
	PauseMenuScript._on_potion_assign_slot_pressed(belt, 1, "health_potion")
	assert_eq(belt.get_slot(1), "health_potion",
		"pressing slot 1 with empty slot must assign the potion")

func test_press_on_slot_holding_this_potion_unassigns():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	PauseMenuScript._on_potion_assign_slot_pressed(belt, 1, "health_potion")
	assert_eq(belt.get_slot(1), "",
		"re-pressing the slot that already holds this potion must unassign")

func test_press_swaps_when_potion_already_in_another_slot():
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	belt.assign(2, "mana_potion")
	# Press slot 2 on a hypothetical health_potion row — health is in slot 1,
	# mana is in slot 2. PotionBelt.assign owns the swap; the helper just
	# delegates.
	PauseMenuScript._on_potion_assign_slot_pressed(belt, 2, "health_potion")
	assert_eq(belt.get_slot(1), "mana_potion", "slot 1 must hold mana after swap")
	assert_eq(belt.get_slot(2), "health_potion", "slot 2 must hold health after swap")

func test_press_on_slot_holding_other_potion_replaces_via_swap():
	# Slot 1 holds mana, mana is in slot 1. Press slot 1 on a health row —
	# health is not anywhere else, so this is a plain replace (no swap source).
	# PotionBelt.assign on an occupied target with a new (not-on-belt) id is
	# a no-op for the existing entry (the new entry just takes the slot),
	# so slot 1 ends up with health and mana is gone.
	var belt := PotionBelt.new()
	belt.assign(1, "mana_potion")
	PauseMenuScript._on_potion_assign_slot_pressed(belt, 1, "health_potion")
	assert_eq(belt.get_slot(1), "health_potion",
		"pressing a slot holding a different potion routes through assign")

func test_owned_potion_rows_reflect_inventory_count_of():
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 3)
	inv.add("shield_potion", 1)
	# mana_potion intentionally not added (count 0)
	var rows := PauseMenuScript._owned_potion_rows(inv)
	# Two rows: only the potions the player owns appear (count > 0).
	assert_eq(rows.size(), 2, "only owned potions show up")
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = r["count"]
	assert_eq(int(by_id.get("health_potion", 0)), 3)
	assert_eq(int(by_id.get("shield_potion", 0)), 1)
	assert_false(by_id.has("mana_potion"), "unowned potions are not listed")

func test_owned_potion_rows_empty_when_inventory_empty():
	var inv := ConsumableInventory.new()
	assert_eq(PauseMenuScript._owned_potion_rows(inv).size(), 0)

func test_owned_potion_rows_null_inventory_returns_empty():
	assert_eq(PauseMenuScript._owned_potion_rows(null).size(), 0)
