extends GutTest

# PRD #132 / issue #133 — CongratulationsMessageBuilder is a pure
# static helper that produces the headline string shown on the
# congratulations screen after a dungeon floor clear. First-boss
# path returns a fixed special message; the repeat path picks a
# random adjective from a curated pool and interpolates it into a
# template. The caller owns the RNG so tests can seed deterministically.

const FIRST_BOSS_MESSAGE := "Congratulations! You survived your first battle with a boss!"

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
