extends GutTest

# Slice #301 (PRD #297) save-compatibility: a save written before the
# BossRoster slice carries no floor_number field, and the boss kind on
# the regenerated graph is whatever the generator picks today — not the
# pre-slice random pool draw. The contract here is "doesn't crash on
# restore", not "preserves the legacy kind". We are not migrating saved
# kinds; the dungeon is regenerated from the seed, and the new generator
# defaults floor_number to 1 so the boss is the Vacuum.

const DungeonRunSerializer = preload("res://scripts/dungeon/dungeon_run_serializer.gd")

func test_legacy_state_without_floor_number_restores_without_crash():
	# Hand-shaped state mirroring a pre-slice save: no floor_number key.
	# Pickleton/ANGRY_PIGEON / etc would have been the random pre-slice pick;
	# we don't need to thread it through because the dungeon is regenerated.
	var legacy_state := {
		"seed": 12345,
		"current_room_id": 0,
		"cleared_room_ids": [],
	}
	var ctrl := DungeonRunSerializer.deserialize(legacy_state)
	assert_not_null(ctrl, "legacy state must restore to a live controller")
	assert_not_null(ctrl.dungeon, "regenerated dungeon must be present")
	# Default floor_number = 1 means the boss is the Vacuum.
	assert_eq(ctrl.dungeon.boss_room().enemy_kind,
		BossRoster.boss_for_floor(1).kind,
		"legacy save restores at floor 1 (Vacuum)")

func test_new_state_round_trips_floor_number():
	var dungeon := DungeonGenerator.generate(77, 3)
	dungeon.depth = 2
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	var state := DungeonRunSerializer.serialize(ctrl, 77)
	assert_eq(state.get("floor_number"), 3,
		"serialize must capture floor_number for slice #301 boss-kind continuity")
	var ctrl2 := DungeonRunSerializer.deserialize(state)
	assert_eq(ctrl2.dungeon.boss_room().enemy_kind,
		BossRoster.boss_for_floor(3).kind,
		"round-tripped floor restores the same per-floor boss kind")
