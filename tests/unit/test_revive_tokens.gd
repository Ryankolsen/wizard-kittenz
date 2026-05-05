extends GutTest

const TMP_PATH := "user://test_revive_save.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# --- TokenInventory.spend ----------------------------------------------------

func test_spend_decrements_and_returns_true_when_funded():
	# Issue scenario 1: Core wiring — spend(1) returns true and decrements.
	var inv := TokenInventory.new()
	inv.count = 3
	assert_true(inv.spend(1), "spend returns true when funded")
	assert_eq(inv.count, 2, "count decrements by 1")

func test_spend_returns_false_and_no_change_when_empty():
	# Issue scenario 2: insufficient tokens.
	var inv := TokenInventory.new()
	assert_false(inv.spend(1), "spend returns false at 0")
	assert_eq(inv.count, 0, "count untouched")

func test_spend_returns_false_when_short_of_amount():
	var inv := TokenInventory.new()
	inv.count = 2
	assert_false(inv.spend(5), "spend(5) on count=2 fails atomically")
	assert_eq(inv.count, 2, "no partial debit")

func test_spend_zero_or_negative_is_noop():
	var inv := TokenInventory.new()
	inv.count = 3
	assert_false(inv.spend(0))
	assert_false(inv.spend(-2))
	assert_eq(inv.count, 3, "non-positive spends never mutate")

# --- TokenInventory.grant ----------------------------------------------------

func test_grant_increments_by_exact_amount():
	# Issue scenario 3: purchase grant adds 5 tokens.
	var inv := TokenInventory.new()
	var granted := inv.grant(5)
	assert_eq(granted, 5)
	assert_eq(inv.count, 5)

func test_grant_accumulates_across_calls():
	var inv := TokenInventory.new()
	inv.grant(5)
	inv.grant(3)
	assert_eq(inv.count, 8)

func test_grant_zero_or_negative_is_noop():
	var inv := TokenInventory.new()
	inv.count = 4
	assert_eq(inv.grant(0), 0)
	assert_eq(inv.grant(-3), 0)
	assert_eq(inv.count, 4)

# --- ReviveSystem.revive -----------------------------------------------------

func test_revive_sets_hp_to_half_max():
	# Issue scenario 4: revive restores player to 50% HP.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 20
	c.hp = 0
	ReviveSystem.revive(c)
	assert_eq(c.hp, 10, "hp restored to 50% of max_hp")

func test_revive_rounds_half_max_hp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 9
	c.hp = 0
	ReviveSystem.revive(c)
	# round(4.5) == 5 in Godot; the floor-1 backstop also doesn't engage here.
	assert_eq(c.hp, 5, "9 max_hp -> revive at 5")

func test_revive_floors_at_one_hp_minimum():
	# Degenerate max_hp=1 must not revive at 0 (would loop the death screen).
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 1
	c.hp = 0
	ReviveSystem.revive(c)
	assert_eq(c.hp, 1, "minimum 1 HP after revive even at max_hp=1")

func test_try_consume_revive_spends_token_and_revives():
	var inv := TokenInventory.new()
	inv.count = 2
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	c.max_hp = 10
	c.hp = 0
	var ok := ReviveSystem.try_consume_revive(c, inv)
	assert_true(ok)
	assert_eq(inv.count, 1, "token spent")
	assert_eq(c.hp, 5, "hp restored to 50%")

func test_try_consume_revive_fails_when_no_tokens():
	# Acceptance criterion: dying with zero tokens shows the buy prompt —
	# the data layer signals that by returning false without mutating the
	# player.
	var inv := TokenInventory.new()
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 10
	c.hp = 0
	var ok := ReviveSystem.try_consume_revive(c, inv)
	assert_false(ok)
	assert_eq(inv.count, 0)
	assert_eq(c.hp, 0, "player stays at 0 hp when revive fails")

func test_try_consume_revive_handles_null_inventory():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 10
	c.hp = 0
	assert_false(ReviveSystem.try_consume_revive(c, null))
	assert_eq(c.hp, 0)

# --- TokenGrantRules ---------------------------------------------------------

func test_tokens_for_level_up_zero_when_no_milestone_crossed():
	# L2 -> L3 crosses no multiple-of-5.
	assert_eq(TokenGrantRules.tokens_for_level_up(2, 3), 0)

func test_tokens_for_level_up_one_when_crossing_single_milestone():
	# L4 -> L5 crosses one milestone.
	assert_eq(TokenGrantRules.tokens_for_level_up(4, 5), 1)

func test_tokens_for_level_up_multiple_when_huge_xp_dump():
	# L4 -> L11 crosses L5 and L10 — two milestones.
	assert_eq(TokenGrantRules.tokens_for_level_up(4, 11), 2)

func test_tokens_for_level_up_returns_zero_when_level_unchanged():
	assert_eq(TokenGrantRules.tokens_for_level_up(7, 7), 0)
	assert_eq(TokenGrantRules.tokens_for_level_up(10, 5), 0,
		"defensive: lower new level can't grant tokens")

func test_tokens_for_boss_kill_and_dungeon_complete_constants():
	assert_gt(TokenGrantRules.tokens_for_boss_kill(), 0,
		"boss kill grants at least one token")
	assert_gt(TokenGrantRules.tokens_for_dungeon_complete(), 0,
		"dungeon completion grants at least one token")

# --- TokenGrantRules.tokens_for_kill ----------------------------------------

func test_tokens_for_kill_grants_boss_bonus_for_boss_enemy():
	# Acceptance: boss kill awards the bonus on top of any milestone grant.
	# Killing a boss with no level-up should still drip the boss-kill token.
	var boss := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	boss.is_boss = true
	assert_eq(TokenGrantRules.tokens_for_kill(boss, 3, 3),
		TokenGrantRules.tokens_for_boss_kill())

func test_tokens_for_kill_no_bonus_for_normal_enemy():
	# Standard enemies don't grant boss tokens — only the milestone drip.
	var slime := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	assert_eq(TokenGrantRules.tokens_for_kill(slime, 3, 3), 0,
		"non-boss kill with no level-up grants nothing")

func test_tokens_for_kill_combines_boss_and_milestone():
	# The kill that crosses L5 AND is a boss should grant both rewards.
	# This is the "epic moment" payout that makes boss kills feel meaningful.
	var boss := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	boss.is_boss = true
	var expected := TokenGrantRules.tokens_for_boss_kill() \
		+ TokenGrantRules.tokens_for_level_up(4, 5)
	assert_eq(TokenGrantRules.tokens_for_kill(boss, 4, 5), expected)

func test_tokens_for_kill_handles_null_enemy_data():
	# Defensive: a future damage-over-time path may award XP with no enemy
	# reference. Null routes through as "not a boss" rather than crashing.
	assert_eq(TokenGrantRules.tokens_for_kill(null, 4, 5),
		TokenGrantRules.tokens_for_level_up(4, 5))
	assert_eq(TokenGrantRules.tokens_for_kill(null, 3, 3), 0)

# --- EnemyData.is_boss -------------------------------------------------------

func test_enemy_data_is_boss_defaults_false():
	# Default false so a generic spawn never accidentally drips boss tokens —
	# the boss flag is opt-in, set by the dungeon spawner on the boss room's
	# enemy.
	var e := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	assert_false(e.is_boss)
	var rat := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	assert_false(rat.is_boss,
		"RAT is the boss enemy *kind* but the flag is set per-spawn, not per-kind")

func test_enemy_data_is_boss_settable():
	var e := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	e.is_boss = true
	assert_true(e.is_boss)

# --- Persistence -------------------------------------------------------------

func test_token_count_round_trips_via_save_manager():
	# Issue scenario 5: persistence — token count survives save/load.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	var inv := TokenInventory.new()
	inv.grant(7)
	var err := SaveManager.save(c, TMP_PATH, null, null, inv)
	assert_eq(err, OK)

	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.revive_tokens, 7, "saved token count survives round-trip")

	var restored := loaded.to_inventory()
	assert_eq(restored.count, 7)

func test_save_without_inventory_defaults_to_zero_tokens():
	# Existing call sites that didn't pass an inventory continue to work —
	# the save lands with revive_tokens=0 instead of erroring.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	SaveManager.save(c, TMP_PATH)
	var loaded := SaveManager.load(TMP_PATH)
	assert_eq(loaded.revive_tokens, 0)

func test_kitten_save_data_dict_round_trip_preserves_tokens():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var inv := TokenInventory.new()
	inv.count = 4
	var sd := KittenSaveData.from_character(c, null, null, inv)
	var restored := KittenSaveData.from_dict(sd.to_dict())
	assert_eq(restored.revive_tokens, 4)

func test_loading_legacy_save_without_token_field_defaults_to_zero():
	# Saves predating this feature have no `revive_tokens` key. from_dict must
	# default to 0 so old saves migrate transparently.
	var legacy := {
		"character_name": "Old",
		"character_class": int(CharacterData.CharacterClass.MAGE),
		"level": 1, "xp": 0, "hp": 8, "max_hp": 8, "attack": 2, "defense": 0,
		"speed": 50.0, "skill_points": 0,
	}
	var sd := KittenSaveData.from_dict(legacy)
	assert_eq(sd.revive_tokens, 0, "missing field reads as zero")

# --- HUD.death_screen_state --------------------------------------------------

func test_death_screen_state_with_tokens_can_revive():
	# Acceptance criterion 1: dying with tokens shows the revive prompt.
	# The HUD branches off `can_revive` to surface the Use Revive button.
	var s := HUD.death_screen_state(3)
	assert_true(s["can_revive"], "tokens > 0 enables the revive path")
	assert_true(s["prompt"].contains("3"),
		"prompt surfaces the current token count to the player")

func test_death_screen_state_zero_tokens_buy_path():
	# Acceptance criterion 2: dying with zero tokens shows the buy prompt.
	# `can_revive=false` is what the HUD checks to swap Use Revive for
	# Buy More.
	var s := HUD.death_screen_state(0)
	assert_false(s["can_revive"], "zero tokens forces the buy path")
	assert_false(s["prompt"].is_empty(),
		"prompt is non-empty so the player sees feedback")

func test_death_screen_state_negative_tokens_treated_as_zero():
	# Defensive: TokenInventory.count can't go negative through normal
	# spend/grant, but a corrupt save or future debuff must not flip
	# can_revive true with a negative count.
	var s := HUD.death_screen_state(-1)
	assert_false(s["can_revive"])

func test_death_screen_state_single_token_singular_path():
	# One token still routes to the revive path — the count-of-one is a
	# common case after a milestone-grant + first death.
	var s := HUD.death_screen_state(1)
	assert_true(s["can_revive"])
	assert_true(s["prompt"].contains("1"))

# --- End-to-end: kill -> level-up milestone -> token granted ----------------

func test_milestone_level_up_grants_token_via_grant_rules():
	# Simulates the Player kill flow without the scene tree: bring a kitten
	# from L4 to L5 by adding XP, then ask the rules how many tokens that
	# crossed and grant them.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 4
	var inv := TokenInventory.new()
	var level_before := c.level
	# xp_to_next_level(4) = 5 + 3*5 = 20
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(4))
	assert_eq(c.level, 5)
	var earned := TokenGrantRules.tokens_for_level_up(level_before, c.level)
	inv.grant(earned)
	assert_eq(inv.count, 1, "milestone L5 awarded one token")

# --- DungeonRunCompletion ----------------------------------------------------

func test_dungeon_run_completion_grants_token_and_records_meta():
	# The boss-cleared hook must fire both side effects in one call: bump
	# the meta tracker (gates unlock conditions) AND drip the token (gates
	# revive economy). Single function so the room-transition layer's
	# terminal branch is one call site.
	var tracker := MetaProgressionTracker.new()
	var inv := TokenInventory.new()
	var granted := DungeonRunCompletion.complete(tracker, inv)
	assert_eq(tracker.dungeons_completed, 1, "meta tracker advances")
	assert_eq(inv.count, TokenGrantRules.tokens_for_dungeon_complete(),
		"inventory grew by the dungeon-complete amount")
	assert_eq(granted, TokenGrantRules.tokens_for_dungeon_complete(),
		"return value matches the granted count for toast UI")

func test_dungeon_run_completion_handles_null_inventory():
	# A fresh-install path where the token inventory hasn't been hydrated
	# yet must not crash — the meta tracker still advances so unlock
	# conditions don't stall.
	var tracker := MetaProgressionTracker.new()
	var granted := DungeonRunCompletion.complete(tracker, null)
	assert_eq(tracker.dungeons_completed, 1)
	assert_eq(granted, 0, "no inventory means no grant reported")

func test_dungeon_run_completion_handles_null_tracker():
	# Symmetric null-safety: a test or alt path without a meta tracker
	# still drips the token. Both args independent so the call site
	# doesn't have to guard each one.
	var inv := TokenInventory.new()
	var granted := DungeonRunCompletion.complete(null, inv)
	assert_eq(granted, TokenGrantRules.tokens_for_dungeon_complete())
	assert_eq(inv.count, TokenGrantRules.tokens_for_dungeon_complete())

func test_dungeon_run_completion_with_both_null_is_safe_noop():
	# Defensive: both null returns 0 cleanly. Used by tests and by any
	# future cutscene path that wants to fire the "completed" event
	# without persistence.
	assert_eq(DungeonRunCompletion.complete(null, null), 0)

func test_dungeon_run_completion_accumulates_across_calls():
	# NOT internally idempotent — a future multi-boss dungeon calls this
	# per boss without a special-case flag. The single-boss case has
	# caller-side idempotency (the boss can only die once per run).
	var tracker := MetaProgressionTracker.new()
	var inv := TokenInventory.new()
	DungeonRunCompletion.complete(tracker, inv)
	DungeonRunCompletion.complete(tracker, inv)
	assert_eq(tracker.dungeons_completed, 2)
	assert_eq(inv.count, 2 * TokenGrantRules.tokens_for_dungeon_complete())
