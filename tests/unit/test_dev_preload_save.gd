extends GutTest

# Issue #516 (PRD #512). tools/dev_preload_save.gd's seed_wall_walker() helper
# pre-unlocks wall_walker on the account written by the local dev seed
# script, so all 4 seeded classes have phase-through available for local
# testing without grinding 5 dungeon clears. Factored as a static helper on
# the tool script itself so it's testable without running the SceneTree
# script as a subprocess.

const DevPreloadSave := preload("res://tools/dev_preload_save.gd")

# --- Slice 1: core wiring ----------------------------------------------------

func test_seed_wall_walker_unlocks_achievement_unclaimed():
	var account := AccountSaveData.new()
	DevPreloadSave.seed_wall_walker(account)
	assert_true(account.achievement_state.has("wall_walker"))
	assert_false(account.achievement_state["wall_walker"]["claimed"])

# --- Slice 2: content details -------------------------------------------------

func test_seed_wall_walker_entry_shape_matches_achievement_service():
	var account := AccountSaveData.new()
	DevPreloadSave.seed_wall_walker(account)
	var entry: Dictionary = account.achievement_state["wall_walker"]
	assert_true(entry.has("unlocked_at"))
	assert_true(entry.has("claimed"))
	assert_true(entry.has("earned_by_slot"))

# --- Slice 3: edge case -------------------------------------------------------

func test_seed_wall_walker_is_idempotent():
	var account := AccountSaveData.new()
	DevPreloadSave.seed_wall_walker(account)
	DevPreloadSave.seed_wall_walker(account)
	assert_eq(account.achievement_state.size(), 1)
	assert_false(account.achievement_state["wall_walker"]["claimed"])
