extends GutTest

const TMP_PATH := "user://test_unlock_save.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# --- Issue tests (4 acceptance scenarios) ---

func test_ninja_locked_until_threshold():
	# Issue test 1: is_unlocked("ninja") is false until dungeons_completed
	# reaches 5, then flips to true.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("ninja", tracker),
		"ninja locked at start (dungeons_completed = 0)")
	for _i in range(4):
		tracker.record_dungeon_complete()
	assert_eq(tracker.dungeons_completed, 4)
	assert_false(registry.is_unlocked("ninja", tracker),
		"still locked at 4/5 dungeons")
	tracker.record_dungeon_complete()
	assert_eq(tracker.dungeons_completed, 5)
	assert_true(registry.is_unlocked("ninja", tracker),
		"unlocks at exactly 5 dungeons (>= threshold)")

func test_check_all_returns_newly_unlocked_ids():
	# Issue test 2: check_all(tracker) returns a list containing "ninja" once
	# the condition is met.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.check_all(tracker).has("ninja"))
	for _i in range(5):
		tracker.record_dungeon_complete()
	var unlocked := registry.check_all(tracker)
	assert_true(unlocked.has("ninja"),
		"check_all surfaces ninja after the threshold is hit")

func test_tier_upgrade_preserves_xp_and_level():
	# Issue test 3: upgrading Mage to Archmage retains xp and level.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	# L3 with 2 xp leftover: thresholds 100+282 = 382 then +2.
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) + 2)
	assert_eq(c.level, 3)
	assert_eq(c.xp, 2)
	var preserved_skill_points := c.skill_points
	var ok: bool = ClassTierUpgrade.upgrade(c)
	assert_true(ok, "mage->archmage upgrade succeeds")
	assert_eq(c.character_class, CharacterData.CharacterClass.ARCHMAGE,
		"class flipped to archmage")
	assert_eq(c.level, 3, "level preserved across upgrade")
	assert_eq(c.xp, 2, "xp preserved across upgrade")
	assert_eq(c.skill_points, preserved_skill_points,
		"skill_points preserved across upgrade")

func test_data_driven_extensibility():
	# Issue test 4: adding a new entry to the conditions data list causes
	# UnlockRegistry to evaluate it without any code change. Same registry
	# class, just different data array.
	var custom_conditions := [
		{"id": "samurai", "stat": "dungeons_completed", "threshold": 3},
		{"id": "necromancer", "stat": "max_level_per_class.mage", "threshold": 10},
	]
	var registry := UnlockRegistry.from_conditions(custom_conditions)
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("samurai", tracker))
	assert_false(registry.is_unlocked("necromancer", tracker))
	for _i in range(3):
		tracker.record_dungeon_complete()
	assert_true(registry.is_unlocked("samurai", tracker),
		"new condition evaluated without code change")
	assert_false(registry.is_unlocked("necromancer", tracker),
		"unmet condition still locked")
	tracker.record_level_reached("mage", 10)
	assert_true(registry.is_unlocked("necromancer", tracker),
		"per-class stat path evaluated against tracker")

# --- Coverage extras ---

func test_starter_classes_always_unlocked():
	# Mage and Thief are starter classes — never gated, regardless of tracker.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_true(registry.is_unlocked("mage", tracker))
	assert_true(registry.is_unlocked("thief", tracker))
	# Case-insensitive folding.
	assert_true(registry.is_unlocked("MAGE", tracker))

func test_unknown_class_id_is_locked():
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("not_a_real_class", tracker))

func test_is_unlocked_with_null_tracker_locks_non_starters():
	# Defensive: unlock check with no tracker reads false for gated ids,
	# but starter classes still pass.
	var registry := UnlockRegistry.make_default()
	assert_false(registry.is_unlocked("ninja", null))
	assert_true(registry.is_unlocked("mage", null), "starter still passes without tracker")

func test_tracker_max_level_is_high_water_mark():
	# record_level_reached only increases the stored max; lower levels are
	# ignored. Same kitten can level down (death/respawn) without losing
	# meta progress.
	var t := MetaProgressionTracker.new()
	t.record_level_reached("mage", 7)
	t.record_level_reached("mage", 3)
	assert_eq(t.max_level_for("mage"), 7, "max kept, not overwritten by lower")
	t.record_level_reached("mage", 10)
	assert_eq(t.max_level_for("mage"), 10, "higher value overwrites")

func test_tracker_per_class_independent():
	# Per-class buckets don't bleed: leveling Mage doesn't unlock a Thief gate.
	var t := MetaProgressionTracker.new()
	t.record_level_reached("mage", 10)
	assert_eq(t.max_level_for("mage"), 10)
	assert_eq(t.max_level_for("thief"), 0, "thief untouched")

func test_tracker_get_stat_paths():
	var t := MetaProgressionTracker.new()
	t.dungeons_completed = 4
	t.record_level_reached("mage", 6)
	assert_eq(t.get_stat("dungeons_completed"), 4)
	assert_eq(t.get_stat("max_level_per_class.mage"), 6)
	assert_eq(t.get_stat("max_level_per_class.thief"), 0,
		"missing key returns 0, not error")
	assert_eq(t.get_stat("garbage_path"), 0, "unknown stat path returns 0")

func test_archmage_unlock_via_mage_level():
	# Archmage gate requires reaching level 5 on a mage.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("archmage", tracker))
	tracker.record_level_reached("mage", 5)
	assert_true(registry.is_unlocked("archmage", tracker))

func test_archmage_has_higher_baseline_than_mage():
	# Tier upgrade replaces base class with improved stats — verify by
	# comparing the per-class baseline curves at the same level.
	var lvl := 3
	assert_gt(
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.ARCHMAGE, lvl),
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, lvl),
		"archmage has more max_hp than mage at the same level")
	assert_gt(
		CharacterData.base_attack_for(CharacterData.CharacterClass.ARCHMAGE, lvl),
		CharacterData.base_attack_for(CharacterData.CharacterClass.MAGE, lvl),
		"archmage hits harder than mage")

func test_tier_upgrade_recomputes_stats_to_target_class():
	# After upgrade, stats reflect the upgraded class's per-level baselines.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 3
	c.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 3)
	c.hp = c.max_hp
	c.attack = CharacterData.base_attack_for(CharacterData.CharacterClass.MAGE, 3)
	ClassTierUpgrade.upgrade(c)
	assert_eq(c.character_class, CharacterData.CharacterClass.ARCHMAGE)
	assert_eq(c.max_hp,
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.ARCHMAGE, 3),
		"max_hp recomputed for archmage at level 3")
	assert_eq(c.attack,
		CharacterData.base_attack_for(CharacterData.CharacterClass.ARCHMAGE, 3),
		"attack recomputed for archmage")
	assert_lte(c.hp, c.max_hp, "hp clamped to new max")

func test_tier_upgrade_no_op_when_no_target():
	# Tier-2 classes (Archmage, Master Thief, Shadow Ninja) have no further
	# upgrade in TIER_MAP — upgrade should return false and leave the
	# character alone. Picks Archmage to pin "already-upgraded class can't
	# re-upgrade" without depending on a base class staying unmapped.
	var c := CharacterData.make_new(CharacterData.CharacterClass.ARCHMAGE)
	var ok: bool = ClassTierUpgrade.upgrade(c)
	assert_false(ok, "no-op when target tier isn't registered")
	assert_eq(c.character_class, CharacterData.CharacterClass.ARCHMAGE,
		"class unchanged on no-op")

func test_save_manager_round_trips_meta_tracker():
	# Tracker state survives the JSON save/load.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	var tree := SkillTree.make_mage_tree()
	var tracker := MetaProgressionTracker.new()
	tracker.dungeons_completed = 4
	tracker.record_level_reached("mage", 6)
	tracker.record_level_reached("thief", 2)
	var err := SaveManager.save(c, TMP_PATH, tree, tracker)
	assert_eq(err, OK)

	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.dungeons_completed, 4)
	var restored := loaded.to_tracker()
	assert_eq(restored.dungeons_completed, 4)
	assert_eq(restored.max_level_for("mage"), 6)
	assert_eq(restored.max_level_for("thief"), 2)

func test_newly_unlocked_diff():
	# newly_unlocked returns only the ids that flipped this transition.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var prev := registry.check_all(tracker)
	for _i in range(5):
		tracker.record_dungeon_complete()
	var new_ids := registry.newly_unlocked(prev, tracker)
	assert_true(new_ids.has("ninja"))
	# A second call with the latest snapshot finds nothing new.
	var again := registry.newly_unlocked(registry.check_all(tracker), tracker)
	assert_eq(again.size(), 0, "no further transitions when already current")

func test_check_all_does_not_include_starter_classes():
	# Starter classes are *always* unlocked but they aren't gated, so the
	# registry's "unlocked from gate" list shouldn't surface them. Keeps
	# the unlock-progress screen focused on what the player earned.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	for _i in range(5):
		tracker.record_dungeon_complete()
	var unlocked := registry.check_all(tracker)
	assert_false(unlocked.has("mage"), "starter mage not included")
	assert_false(unlocked.has("thief"), "starter thief not included")

func test_character_factory_handles_archmage():
	var klass: int = CharacterFactory.class_from_name("archmage")
	assert_eq(klass, CharacterData.CharacterClass.ARCHMAGE)
	assert_eq(CharacterFactory.name_from_class(CharacterData.CharacterClass.ARCHMAGE), "archmage")

# --- Tier-2 upgrades for Thief and Ninja ------------------------------------

func test_master_thief_has_higher_baseline_than_thief():
	# Tier upgrade replaces base class with improved stats — same shape as
	# the archmage check, applied to the thief upgrade path.
	var lvl := 3
	assert_gt(
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.MASTER_THIEF, lvl),
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.THIEF, lvl),
		"master thief has more max_hp than thief at the same level")
	assert_gt(
		CharacterData.base_attack_for(CharacterData.CharacterClass.MASTER_THIEF, lvl),
		CharacterData.base_attack_for(CharacterData.CharacterClass.THIEF, lvl),
		"master thief hits harder than thief")
	assert_gt(
		CharacterData.base_speed_for(CharacterData.CharacterClass.MASTER_THIEF, lvl),
		CharacterData.base_speed_for(CharacterData.CharacterClass.THIEF, lvl),
		"master thief stays the fastest archetype (speed uplift, not regression)")

func test_shadow_ninja_has_higher_baseline_than_ninja():
	var lvl := 3
	assert_gt(
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.SHADOW_NINJA, lvl),
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.NINJA, lvl),
		"shadow ninja has more max_hp than ninja at the same level")
	assert_gt(
		CharacterData.base_attack_for(CharacterData.CharacterClass.SHADOW_NINJA, lvl),
		CharacterData.base_attack_for(CharacterData.CharacterClass.NINJA, lvl),
		"shadow ninja hits harder than ninja")

func test_tier_upgrade_thief_to_master_thief_preserves_progression():
	# Same preserves-progression contract as the mage->archmage case.
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) + 2)  # L3 with 2 xp leftover
	assert_eq(c.level, 3)
	assert_eq(c.xp, 2)
	var preserved_skill_points := c.skill_points
	var ok: bool = ClassTierUpgrade.upgrade(c)
	assert_true(ok, "thief->master thief upgrade succeeds")
	assert_eq(c.character_class, CharacterData.CharacterClass.MASTER_THIEF,
		"class flipped to master thief")
	assert_eq(c.level, 3, "level preserved across upgrade")
	assert_eq(c.xp, 2, "xp preserved across upgrade")
	assert_eq(c.skill_points, preserved_skill_points,
		"skill_points preserved across upgrade")
	assert_eq(c.max_hp,
		CharacterData.base_max_hp_for(CharacterData.CharacterClass.MASTER_THIEF, 3),
		"max_hp recomputed for master thief")

func test_tier_upgrade_ninja_to_shadow_ninja_preserves_progression():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) + 2)
	assert_eq(c.level, 3)
	var ok: bool = ClassTierUpgrade.upgrade(c)
	assert_true(ok, "ninja->shadow ninja upgrade succeeds")
	assert_eq(c.character_class, CharacterData.CharacterClass.SHADOW_NINJA)
	assert_eq(c.level, 3, "level preserved across upgrade")
	assert_eq(c.attack,
		CharacterData.base_attack_for(CharacterData.CharacterClass.SHADOW_NINJA, 3),
		"attack recomputed for shadow ninja")

func test_character_factory_handles_tier_2_thief_and_ninja():
	# The lowercase ids round-trip through the factory the same way
	# "archmage" does — keeps name_from_class consistent for any tracker /
	# UnlockRegistry call that keys on the lowercase id string.
	assert_eq(
		CharacterFactory.class_from_name("master_thief"),
		CharacterData.CharacterClass.MASTER_THIEF)
	assert_eq(
		CharacterFactory.name_from_class(CharacterData.CharacterClass.MASTER_THIEF),
		"master_thief")
	assert_eq(
		CharacterFactory.class_from_name("shadow_ninja"),
		CharacterData.CharacterClass.SHADOW_NINJA)
	assert_eq(
		CharacterFactory.name_from_class(CharacterData.CharacterClass.SHADOW_NINJA),
		"shadow_ninja")

# --- Tier-2 gameplay-earnable unlock gates ----------------------------------
# PRD #26 user story 43 ("IAP items achievable through gameplay too"). The
# paid path through PaidUnlockInventory is wired by 3327f3e; this gate is the
# gameplay-earned counterpart. Mirrors the existing archmage gate shape:
# reach level 5 on the base class -> tier-2 id flips unlocked in the registry.

func test_master_thief_unlock_via_thief_level():
	# Symmetric to archmage's mage-level-5 gate — earnable path for the
	# paid tier-2 thief upgrade.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("master_thief", tracker),
		"locked at start (thief level 0)")
	tracker.record_level_reached("thief", 4)
	assert_false(registry.is_unlocked("master_thief", tracker),
		"still locked at thief level 4 (< threshold)")
	tracker.record_level_reached("thief", 5)
	assert_true(registry.is_unlocked("master_thief", tracker),
		"unlocks at exactly thief level 5 (>= threshold)")

func test_shadow_ninja_unlock_via_ninja_level():
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	assert_false(registry.is_unlocked("shadow_ninja", tracker),
		"locked at start (ninja level 0)")
	tracker.record_level_reached("ninja", 5)
	assert_true(registry.is_unlocked("shadow_ninja", tracker),
		"unlocks at ninja level 5")

func test_tier_2_gates_do_not_bleed_across_base_classes():
	# Leveling Mage shouldn't unlock Master Thief / Shadow Ninja, and
	# vice-versa. The per-class stat paths gate each tier-2 id on the
	# matching base class only — same independence contract the
	# tracker pins for level buckets.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	tracker.record_level_reached("mage", 5)
	assert_true(registry.is_unlocked("archmage", tracker),
		"mage level 5 unlocks archmage")
	assert_false(registry.is_unlocked("master_thief", tracker),
		"mage level 5 does NOT unlock master_thief")
	assert_false(registry.is_unlocked("shadow_ninja", tracker),
		"mage level 5 does NOT unlock shadow_ninja")
	tracker.record_level_reached("thief", 5)
	assert_false(registry.is_unlocked("shadow_ninja", tracker),
		"thief level 5 does NOT unlock shadow_ninja")

func test_check_all_surfaces_tier_2_unlocks():
	# The screen layer / "new class available!" toast reads check_all
	# to project unlock state. All three tier-2 ids should surface once
	# their respective gameplay conditions are met.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	tracker.record_level_reached("mage", 5)
	tracker.record_level_reached("thief", 5)
	tracker.record_level_reached("ninja", 5)
	var unlocked := registry.check_all(tracker)
	assert_true(unlocked.has("archmage"), "archmage surfaced")
	assert_true(unlocked.has("master_thief"), "master_thief surfaced")
	assert_true(unlocked.has("shadow_ninja"), "shadow_ninja surfaced")

func test_paid_unlock_bypasses_tier_2_thresholds():
	# PRD's "earnable through gameplay OR purchased" parity for the
	# tier-2 ids — paid grant lights up the id even with a fresh tracker.
	var registry := UnlockRegistry.make_default()
	var tracker := MetaProgressionTracker.new()
	var paid := PaidUnlockInventory.new()
	assert_false(registry.is_unlocked("master_thief", tracker, paid),
		"master_thief locked before purchase or gameplay")
	paid.grant("master_thief")
	assert_true(registry.is_unlocked("master_thief", tracker, paid),
		"paid grant bypasses thief level threshold")
	assert_false(registry.is_unlocked("shadow_ninja", tracker, paid),
		"shadow_ninja still locked (no paid grant for it)")
	paid.grant("shadow_ninja")
	assert_true(registry.is_unlocked("shadow_ninja", tracker, paid),
		"paid grant bypasses ninja level threshold")
