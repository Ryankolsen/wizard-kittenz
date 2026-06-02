extends GutTest

# Skill-point respec migration (PRD #316 / issue #319). On first load
# post-tier-rules a pre-update character has its allocated stat bonuses
# refunded back to skill_points and its allocated_points dict zeroed,
# so the player re-spec's under the new caps/costs. Detected via the
# schema_version flag — runs once per character.

const CURRENT := SkillPointRespec.CURRENT_VERSION

func _legacy_wizard() -> CharacterData:
	# Build a pre-tier (schema_version = 0) Wizard with the post-#318 base
	# stats and a couple of allocations the player would have made under
	# the old rules. Wizard archetype so magic_attack is Primary (1 SP/pt)
	# and defense is Off-stat (2 SP/pt).
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Legacy")
	c.schema_version = 0
	return c

func test_pre_update_save_triggers_respec() -> void:
	var c := _legacy_wizard()
	# Simulate prior allocations: +3 magic_attack (Primary, 1 SP/pt = 3 SP),
	# +2 defense (Off-stat, 2 SP/pt = 4 SP). Total previously-spent: 7 SP.
	var base_ma: int = c.magic_attack
	var base_def: int = c.defense
	c.magic_attack += 3 * int(StatAllocator.INT_INCREMENTS["magic_attack"])
	c.defense += 2 * int(StatAllocator.INT_INCREMENTS["defense"])
	c.allocated_points = {"magic_attack": 3, "defense": 2}
	c.skill_points = 0

	var ran := SkillPointRespec.migrate(c)

	assert_true(ran, "Migration should report having run")
	assert_eq(c.skill_points, 7, "All previously-spent SP refunded")
	assert_eq(c.magic_attack, base_ma, "magic_attack restored to baseline")
	assert_eq(c.defense, base_def, "defense restored to baseline")
	assert_eq(c.allocated_points, {}, "allocated_points zeroed")

func test_base_stats_unchanged_by_migration() -> void:
	# A pre-tier Wizard with no allocations: migration runs (version bump
	# only) and leaves every base stat at the make_new baseline.
	var c := _legacy_wizard()
	SkillPointRespec.migrate(c)
	var baseline := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.max_hp, baseline.max_hp)
	assert_eq(c.attack, baseline.attack)
	assert_eq(c.defense, baseline.defense)
	assert_eq(c.magic_attack, baseline.magic_attack)
	assert_eq(c.max_mp, baseline.max_mp)

func test_equipped_item_bonuses_unchanged_by_migration() -> void:
	# Items live on ItemInventory, not on CharacterData — what the migration
	# must not do is claw back stat values that came from equipping. Simulate
	# a +2 defense item by raising defense above baseline with no matching
	# allocated_points entry: migration must leave that surplus in place.
	var c := _legacy_wizard()
	var base_def: int = c.defense
	c.defense = base_def + 2  # item bonus, not tracked in allocated_points
	SkillPointRespec.migrate(c)
	assert_eq(c.defense, base_def + 2, "Item-granted bonus preserved")

func test_schema_version_updated_after_migration() -> void:
	var c := _legacy_wizard()
	SkillPointRespec.migrate(c)
	assert_eq(c.schema_version, CURRENT)

func test_post_update_save_is_noop() -> void:
	# Character already at current schema version + some allocation state
	# (as if it were allocated post-tier). Migration must not touch
	# skill_points, stat fields, or allocated_points.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	c.magic_attack += 2 * int(StatAllocator.INT_INCREMENTS["magic_attack"])
	c.allocated_points = {"magic_attack": 2}
	var snapshot_sp := c.skill_points
	var snapshot_ma := c.magic_attack
	var snapshot_alloc := c.allocated_points.duplicate()

	var ran := SkillPointRespec.migrate(c)

	assert_false(ran, "Up-to-date save should be a no-op")
	assert_eq(c.skill_points, snapshot_sp)
	assert_eq(c.magic_attack, snapshot_ma)
	assert_eq(c.allocated_points, snapshot_alloc)

func test_migration_idempotent() -> void:
	# Running migration twice on a pre-update character does not double-refund.
	var c := _legacy_wizard()
	c.magic_attack += 3 * int(StatAllocator.INT_INCREMENTS["magic_attack"])
	c.allocated_points = {"magic_attack": 3}
	c.skill_points = 0

	SkillPointRespec.migrate(c)
	var sp_after_first := c.skill_points
	var ran_second := SkillPointRespec.migrate(c)

	assert_false(ran_second, "Second migration should be a no-op")
	assert_eq(c.skill_points, sp_after_first, "SP must not double-refund")

func test_character_with_zero_allocations_migrates_cleanly() -> void:
	# Pre-tier save with no allocations: no refund, no errors, version bumps.
	var c := _legacy_wizard()
	c.skill_points = 4
	var ran := SkillPointRespec.migrate(c)
	assert_true(ran)
	assert_eq(c.skill_points, 4)
	assert_eq(c.schema_version, CURRENT)

func test_offstat_allocation_refunds_at_double_cost() -> void:
	# Wizard's defense is Off-stat (2 SP/pt). +2 defense = 4 SP refund.
	var c := _legacy_wizard()
	c.defense += 2 * int(StatAllocator.INT_INCREMENTS["defense"])
	c.allocated_points = {"defense": 2}
	c.skill_points = 0
	SkillPointRespec.migrate(c)
	assert_eq(c.skill_points, 4, "Off-stat refunds at 2 SP/pt")

func test_max_hp_allocation_undoes_and_clamps_hp() -> void:
	# allocate() raised both max_hp and hp by 5*pts; migration subtracts the
	# same delta off max_hp and clamps current hp so a damaged character
	# doesn't end up above the new ceiling.
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.schema_version = 0
	var base_max := c.max_hp
	# Simulate post-allocation state: +2 max_hp pts = +10 max_hp, currently
	# damaged down to base_max + 3 (still above the post-respec ceiling).
	c.max_hp = base_max + 10
	c.hp = base_max + 3
	c.allocated_points = {"max_hp": 2}
	SkillPointRespec.migrate(c)
	assert_eq(c.max_hp, base_max, "max_hp restored to baseline")
	assert_eq(c.hp, base_max, "hp clamped to new ceiling")

func test_apply_to_runs_migration_on_legacy_save() -> void:
	# Round-trip path: a save dict written before this slice has no
	# schema_version / allocated_points keys, so the loaded character
	# should be migrated automatically and emerge at CURRENT_VERSION.
	var save := KittenSaveData.from_dict({
		"character_class": int(CharacterData.CharacterClass.BATTLE_KITTEN),
		"skill_points": 0,
		# attack pre-bumped to simulate prior allocation (Primary, 1 SP/pt).
		"attack": CharacterData.base_attack_for(CharacterData.CharacterClass.BATTLE_KITTEN, 1) + 4,
		"allocated_points": {"attack": 4},
	})
	var c := CharacterData.new()
	save.apply_to(c)
	assert_eq(c.schema_version, CURRENT, "apply_to bumps schema_version")
	assert_eq(c.allocated_points, {}, "apply_to zeroes allocations")
	assert_eq(c.skill_points, 4, "apply_to refunds the 4 spent SP")
	assert_eq(c.attack, CharacterData.base_attack_for(CharacterData.CharacterClass.BATTLE_KITTEN, 1))

func test_apply_to_noop_on_current_save() -> void:
	# Save already at CURRENT version: apply_to copies through, no respec.
	var save := KittenSaveData.from_dict({
		"character_class": int(CharacterData.CharacterClass.BATTLE_KITTEN),
		"skill_points": 0,
		"attack": CharacterData.base_attack_for(CharacterData.CharacterClass.BATTLE_KITTEN, 1) + 3,
		"allocated_points": {"attack": 3},
		"schema_version": CURRENT,
	})
	var c := CharacterData.new()
	save.apply_to(c)
	assert_eq(c.skill_points, 0)
	assert_eq(c.allocated_points, {"attack": 3})
	assert_eq(c.attack, CharacterData.base_attack_for(CharacterData.CharacterClass.BATTLE_KITTEN, 1) + 3)
