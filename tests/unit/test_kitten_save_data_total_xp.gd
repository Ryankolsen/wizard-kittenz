extends GutTest

# Lifetime total_xp persistence (issue #413/#414). Mirrors the xp field's
# save/load/slot-carryover paths; legacy data predating this field defaults
# to 0.

func test_from_character_carries_total_xp():
	var c := CharacterData.new()
	c.total_xp = 500
	var s := KittenSaveData.from_character(c)
	assert_eq(s.total_xp, 500)

func test_total_xp_round_trips_through_dict():
	var save := KittenSaveData.new()
	save.total_xp = 500
	var d := save.to_dict()
	var reloaded := KittenSaveData.from_dict(d)
	assert_eq(reloaded.total_xp, 500)

func test_legacy_save_defaults_total_xp_to_zero():
	var reloaded := KittenSaveData.from_dict({})
	assert_eq(reloaded.total_xp, 0)

func test_slot_copy_carries_total_xp():
	var slot := CharacterSlotData.new()
	slot.total_xp = 750
	var copied := CharacterSlotData.from_dict(slot.to_dict())
	assert_eq(copied.total_xp, 750)
