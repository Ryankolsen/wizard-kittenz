extends GutTest

# Issue #515 (PRD #512). AchievementEffects maps specific achievement unlocks
# to permanent gameplay effects, starting with "grant wall phase-through" for
# wall_walker (#514). Kept out of AchievementService itself so that stays
# reward-shape generic (gold/potion/item/tome/none).

func before_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())

func after_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())
	GameState.current_character = null

func _make_player() -> Player:
	var p := Player.new()
	add_child_autofree(p)
	return p

# --- Slice 1: core wiring ---------------------------------------------------

func test_live_unlock_grants_phase_through_immediately():
	GameState.achievement_service = AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	var p := _make_player()
	assert_false(p.can_phase_through_walls(), "fresh player must start wall-blocked")
	GameState.achievement_service.increment_counter("dungeons_completed", 5)
	assert_true(p.can_phase_through_walls(),
		"wall_walker unlock must grant phase-through to the active player with no explicit apply call")

# --- Slice 2: session-start re-apply for an already-unlocked achievement ----

func test_player_start_reapplies_phase_through_for_already_unlocked_achievement():
	var account := AccountSaveData.new()
	account.achievement_state["wall_walker"] = {
		"unlocked_at": 0,
		"claimed": false,
		"earned_by_slot": "",
	}
	GameState.achievement_service = AchievementService.new(account, AchievementCatalog.all())
	var p := _make_player()
	assert_true(p.can_phase_through_walls(),
		"a fresh player must start with phase-through already enabled when wall_walker is already unlocked")

# --- Slice 3: edge cases -----------------------------------------------------

func test_fresh_account_with_no_unlocks_still_defaults_to_wall_blocked():
	GameState.achievement_service = AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	var p := _make_player()
	assert_false(p.can_phase_through_walls(),
		"a fresh account with no achievements unlocked must not enable phase-through")

func test_unrelated_achievement_unlock_does_not_enable_phase_through():
	GameState.achievement_service = AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	var p := _make_player()
	GameState.achievement_service.record_event("bar_entered")
	assert_false(p.can_phase_through_walls(),
		"unlocking an unrelated achievement must not enable phase-through")

func test_retriggering_past_threshold_is_idempotent():
	GameState.achievement_service = AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	var p := _make_player()
	GameState.achievement_service.increment_counter("dungeons_completed", 5)
	assert_true(p.can_phase_through_walls())
	GameState.achievement_service.increment_counter("dungeons_completed", 1)
	assert_true(p.can_phase_through_walls(),
		"re-triggering the counter past an already-unlocked threshold must not error and must leave phase-through enabled")
