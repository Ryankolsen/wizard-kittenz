extends GutTest

# PRD #132 / issue #133 — CongratulationsMessageBuilder is a pure
# static helper that produces the headline string shown on the
# congratulations screen after a dungeon floor clear. First-boss
# path returns a fixed special message; the repeat path picks a
# random adjective from a curated pool and interpolates it into a
# template. The caller owns the RNG so tests can seed deterministically.

const FIRST_BOSS_MESSAGE := "Congratulations on your first boss kill!"

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_first_boss_path_returns_exact_message():
	var rng := _rng(0)
	assert_eq(CongratulationsMessageBuilder.build(true, rng), FIRST_BOSS_MESSAGE)

func test_repeat_path_returns_non_empty_string():
	var rng := _rng(1)
	var msg := CongratulationsMessageBuilder.build(false, rng)
	assert_gt(msg.length(), 0)

func test_repeat_path_contains_pool_adjective():
	# Seed the RNG and confirm the result contains one of the known
	# adjectives. Iterate a handful of seeds so we cover multiple
	# adjective selections, not just one branch.
	for s in range(10):
		var rng := _rng(s)
		var msg := CongratulationsMessageBuilder.build(false, rng)
		var matched := false
		for adj in CongratulationsMessageBuilder.ADJECTIVE_POOL:
			if msg.find(adj) != -1:
				matched = true
				break
		assert_true(matched, "message '%s' should contain one of the pool adjectives" % msg)

func test_all_pool_entries_are_non_empty():
	assert_gt(CongratulationsMessageBuilder.ADJECTIVE_POOL.size(), 0)
	for adj in CongratulationsMessageBuilder.ADJECTIVE_POOL:
		assert_true(adj is String, "pool entry should be a String")
		assert_gt(String(adj).length(), 0, "pool entry should be non-empty")

func test_repeat_path_does_not_return_first_boss_message():
	for s in range(10):
		var rng := _rng(s)
		var msg := CongratulationsMessageBuilder.build(false, rng)
		assert_ne(msg, FIRST_BOSS_MESSAGE)

# PRD #297 / slice #302 — when a boss display name is supplied, the
# repeat-path message names the defeated boss instead of falling back to
# the generic "the boss" string.
func test_repeat_path_includes_supplied_boss_name():
	var rng := _rng(7)
	var msg := CongratulationsMessageBuilder.build(false, rng, "Sir Pickleton")
	assert_true(msg.find("Sir Pickleton") != -1, "message '%s' should name the boss" % msg)

func test_repeat_path_with_boss_name_does_not_say_the_boss():
	# Regression guard: if the lookup silently no-ops we'd still print the
	# legacy generic phrasing alongside the real name. With a named boss
	# supplied, "the boss" should not appear.
	for s in range(10):
		var rng := _rng(s)
		var msg := CongratulationsMessageBuilder.build(false, rng, "Old Lady Pearl")
		assert_eq(msg.find("the boss"), -1, "message '%s' should not contain 'the boss'" % msg)

func test_repeat_path_uses_roster_name_for_floor_4():
	# Tracks PRD acceptance: Floor 4 -> Trash Panda Tyrone.
	var rng := _rng(0)
	var info := BossRoster.boss_for_floor(4)
	var msg := CongratulationsMessageBuilder.build(false, rng, info.display_name)
	assert_true(msg.find("Trash Panda Tyrone") != -1, "message '%s' should contain Floor 4 boss name" % msg)

func test_repeat_path_empty_name_falls_back_to_the_boss():
	# Defensive: callers that pass "" (legacy path, missing roster) still
	# render a grammatical sentence using the generic phrasing.
	var rng := _rng(0)
	var msg := CongratulationsMessageBuilder.build(false, rng, "")
	assert_true(msg.find("the boss") != -1, "empty name should fall back to 'the boss', got '%s'" % msg)

func test_first_boss_path_ignores_boss_name():
	var rng := _rng(0)
	assert_eq(CongratulationsMessageBuilder.build(true, rng, "Sir Pickleton"), FIRST_BOSS_MESSAGE)
