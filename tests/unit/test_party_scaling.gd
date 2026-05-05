extends GutTest

# --- compute_floor -----------------------------------------------------------

func test_compute_floor_returns_minimum_level():
	# Issue scenario 1: PartyScaler.compute_floor([3, 7, 10]) == 3.
	assert_eq(PartyScaler.compute_floor([3, 7, 10]), 3)

func test_compute_floor_handles_unsorted_input():
	assert_eq(PartyScaler.compute_floor([10, 3, 7]), 3)
	assert_eq(PartyScaler.compute_floor([7, 10, 3]), 3)

func test_compute_floor_handles_duplicates():
	assert_eq(PartyScaler.compute_floor([5, 5, 5]), 5)

func test_compute_floor_single_member_party():
	assert_eq(PartyScaler.compute_floor([12]), 12)

func test_compute_floor_empty_array_returns_safe_default():
	# Degenerate "party of zero" must not blow up downstream stat lookups.
	assert_eq(PartyScaler.compute_floor([]), 1)

# --- scale_stats -------------------------------------------------------------

func test_scale_stats_reduces_level_10_to_floor_3_baseline():
	# Issue scenario 2: a level-10 player in a level-3 party gets
	# stats equivalent to level-3 baseline for that class.
	var lvl_10 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	lvl_10.level = 10
	lvl_10.max_hp = CharacterData.base_max_hp_for(lvl_10.character_class, 10)
	lvl_10.hp = lvl_10.max_hp

	var scaled := PartyScaler.scale_stats(lvl_10, 3)
	assert_eq(scaled.level, 3, "effective level matches floor")
	assert_eq(scaled.max_hp, CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 3),
		"max_hp matches per-class level-3 baseline")
	assert_eq(scaled.attack, CharacterData.base_attack_for(CharacterData.CharacterClass.MAGE, 3))
	assert_eq(scaled.defense, CharacterData.base_defense_for(CharacterData.CharacterClass.MAGE, 3))
	assert_lt(scaled.max_hp, lvl_10.max_hp, "scaled max_hp is strictly lower than real")

func test_scale_stats_preserves_class_and_name():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
	c.level = 8
	c.max_hp = CharacterData.base_max_hp_for(c.character_class, 8)
	c.hp = c.max_hp
	var scaled := PartyScaler.scale_stats(c, 2)
	assert_eq(scaled.character_class, CharacterData.CharacterClass.NINJA)
	assert_eq(scaled.character_name, "Shadow")

func test_scale_stats_preserves_xp_and_skill_points():
	# Scaling is a stat view, not a progression rollback — xp/sp must carry.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 5
	c.xp = 11
	c.skill_points = 3
	var scaled := PartyScaler.scale_stats(c, 2)
	assert_eq(scaled.xp, 11, "xp carries to scaled view")
	assert_eq(scaled.skill_points, 3, "skill_points carry to scaled view")

func test_scale_stats_floor_player_returns_identical_stats():
	# Issue scenario 3: scale factor of 1.0 for the floor player.
	var lvl_3 := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "Whisker")
	lvl_3.level = 3
	lvl_3.max_hp = CharacterData.base_max_hp_for(lvl_3.character_class, 3)
	lvl_3.hp = lvl_3.max_hp
	var scaled := PartyScaler.scale_stats(lvl_3, 3)
	assert_eq(scaled.level, lvl_3.level)
	assert_eq(scaled.max_hp, lvl_3.max_hp)
	assert_eq(scaled.attack, lvl_3.attack)
	assert_eq(scaled.defense, lvl_3.defense)
	assert_eq(scaled.speed, lvl_3.speed)
	assert_eq(scaled.hp, lvl_3.hp)

func test_scale_stats_below_floor_returns_clone_not_input():
	# A level-1 player in a level-3 party shouldn't be artificially boosted.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var scaled := PartyScaler.scale_stats(c, 3)
	assert_eq(scaled.level, c.level, "no upscaling — level stays at 1")
	assert_ne(scaled, c, "returns a fresh clone, not the input reference")

func test_scale_stats_returns_new_instance_not_mutating_input():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 10
	c.max_hp = CharacterData.base_max_hp_for(c.character_class, 10)
	c.hp = c.max_hp
	var max_hp_before := c.max_hp
	var scaled := PartyScaler.scale_stats(c, 3)
	assert_eq(c.level, 10, "input level untouched")
	assert_eq(c.max_hp, max_hp_before, "input max_hp untouched")
	assert_ne(scaled, c, "returns a new CharacterData")

# --- XPSystem.award ----------------------------------------------------------

func test_xp_system_award_use_real_level_true_routes_xp_to_real_stats():
	# Issue scenario 4: scaled session XP applies to real_stats.xp.
	var real := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	real.level = 10
	var pm := PartyMember.from_character(real)
	pm.apply_scaling(3)
	var effective_xp_before := pm.effective_stats.xp
	XPSystem.award(pm, 4, true)
	assert_eq(pm.real_stats.xp, 4, "XP lands on real_stats")
	assert_eq(pm.effective_stats.xp, effective_xp_before, "effective_stats.xp unchanged")

func test_xp_system_award_use_real_level_false_routes_xp_to_effective_stats():
	# Optional path for any future scaled-XP pool. Today: routes to effective.
	var real := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var pm := PartyMember.from_character(real)
	XPSystem.award(pm, 3, false)
	assert_eq(pm.effective_stats.xp, 3)
	assert_eq(pm.real_stats.xp, 0, "real_stats.xp untouched")

func test_xp_system_award_defaults_to_real_level():
	# Default is the safer, expected behavior — real progression always advances.
	var pm := PartyMember.from_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))
	XPSystem.award(pm, 2)
	assert_eq(pm.real_stats.xp, 2)
	assert_eq(pm.effective_stats.xp, 0)

func test_xp_system_award_zero_or_negative_is_noop():
	var pm := PartyMember.from_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))
	assert_eq(XPSystem.award(pm, 0, true), 0)
	assert_eq(pm.real_stats.xp, 0)
	assert_eq(XPSystem.award(pm, -5, true), 0)
	assert_eq(pm.real_stats.xp, 0)

# --- PartyMember -------------------------------------------------------------

func test_party_member_from_character_starts_real_and_effective_equal():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
	var pm := PartyMember.from_character(c)
	assert_eq(pm.real_stats.level, pm.effective_stats.level)
	assert_eq(pm.real_stats.max_hp, pm.effective_stats.max_hp)
	assert_ne(pm.real_stats, pm.effective_stats, "effective is a clone, not the same reference")

func test_party_member_apply_scaling_only_mutates_effective():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 7
	c.max_hp = CharacterData.base_max_hp_for(c.character_class, 7)
	c.hp = c.max_hp
	var pm := PartyMember.from_character(c)
	pm.apply_scaling(2)
	assert_eq(pm.real_stats.level, 7, "real_stats untouched by scaling")
	assert_eq(pm.effective_stats.level, 2, "effective_stats reduced to floor")

# --- remove_scaling ----------------------------------------------------------

func test_remove_scaling_restores_effective_to_real():
	# Issue scenario 5: session-end inverse — drop scaling, restore real stats.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 10
	c.max_hp = CharacterData.base_max_hp_for(c.character_class, 10)
	c.hp = c.max_hp
	var pm := PartyMember.from_character(c)
	pm.apply_scaling(3)
	assert_ne(pm.effective_stats.level, pm.real_stats.level, "fixture: scaled state")
	PartyScaler.remove_scaling(pm)
	assert_eq(pm.effective_stats.level, pm.real_stats.level)
	assert_eq(pm.effective_stats.max_hp, pm.real_stats.max_hp)
	assert_ne(pm.effective_stats, pm.real_stats, "effective is still a clone, not the same reference")

# --- HUD format --------------------------------------------------------------

func test_format_hud_level_scaled_session_shows_real_and_effective():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 10
	var pm := PartyMember.from_character(c)
	pm.apply_scaling(3)
	assert_eq(PartyScaler.format_hud_level(pm), "Lv.10 (Lv.3)")

func test_format_hud_level_solo_session_shows_single_level():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.level = 10
	var pm := PartyMember.from_character(c)
	# No scaling applied — both stat snapshots agree.
	assert_eq(PartyScaler.format_hud_level(pm), "Lv.10")

# --- end-to-end --------------------------------------------------------------

func test_full_session_flow_xp_progresses_real_level_after_unscale():
	# A level-10 mage joins a level-3 party. They earn enough XP to level up
	# their REAL level. Session ends; remove_scaling drops the scaled view
	# and the real level is correctly higher than where they started.
	var real := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	real.level = 10
	real.max_hp = CharacterData.base_max_hp_for(real.character_class, 10)
	real.hp = real.max_hp
	var pm := PartyMember.from_character(real)
	pm.apply_scaling(3)
	var real_lvl_before := pm.real_stats.level
	# xp_to_next_level(10) = 5 + 9*5 = 50
	XPSystem.award(pm, ProgressionSystem.xp_to_next_level(10))
	assert_eq(pm.real_stats.level, real_lvl_before + 1, "real level advanced from XP")
	PartyScaler.remove_scaling(pm)
	assert_eq(pm.effective_stats.level, pm.real_stats.level, "post-session view matches real")
