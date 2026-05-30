extends GutTest

# Slice #301 (PRD #297): seam catch for slice #300 (HITL sprite drop).
# Every floor 1..10 must have both left- and right-facing PNGs reachable
# via ResourceLoader. Slice #300 ships those PNGs; until then this test
# is the alarm that names which floors still need art.
#
# Pending while slice #300 (HITL) is open — the assertion bodies are
# preserved so flipping `pending(...)` to `assert_*(...)` is a one-line
# re-arm once the sprites land. The first floor (Vacuum) is asserted live
# since its sprite already exists on disk.

func test_floor_1_vacuum_sprite_exists():
	var info := BossRoster.boss_for_floor(1)
	assert_true(ResourceLoader.exists(info.sprite_left_path),
		"missing %s" % info.sprite_left_path)
	assert_true(ResourceLoader.exists(info.sprite_right_path),
		"missing %s" % info.sprite_right_path)

func test_floors_2_through_10_sprites_exist():
	# Pending: slice #300 (HITL) produces the left/right PNGs for each new
	# boss. Re-arm by replacing pending() with the assert_true lines below.
	var missing := []
	for floor_n in range(2, 11):
		var info := BossRoster.boss_for_floor(floor_n)
		if not ResourceLoader.exists(info.sprite_left_path):
			missing.append(info.sprite_left_path)
		if not ResourceLoader.exists(info.sprite_right_path):
			missing.append(info.sprite_right_path)
	if missing.is_empty():
		assert_true(true, "all 9 boss sprite pairs exist on disk")
	else:
		pending("slice #300 (HITL) still owes %d sprite files: %s" % [missing.size(), str(missing)])
