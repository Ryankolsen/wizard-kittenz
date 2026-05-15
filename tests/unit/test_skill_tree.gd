extends GutTest

const TMP_PATH := "user://test_skill_save.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

var _character: CharacterData
var _tree: SkillTree
var _manager: SkillTreeManager

func _setup(skill_points: int) -> void:
	_character = CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	_character.skill_points = skill_points
	_tree = SkillTree.make_mage_tree()
	_manager = SkillTreeManager.make(_tree, _character)

# --- Issue tests ---

func test_unlock_succeeds_with_sufficient_points():
	# Issue test 1: unlock("fireball") with sufficient points -> success +
	# fireball.unlocked == true.
	_setup(1)
	var ok: bool = _manager.unlock("fireball")
	assert_true(ok, "unlock returns true on success")
	assert_true(_tree.find("fireball").unlocked, "fireball.unlocked flips to true")
	assert_eq(_character.skill_points, 0, "skill point spent on unlock")

func test_unlock_blocked_by_missing_prerequisite():
	# Issue test 2: unlocking frost_nova before fireball is rejected and
	# leaves frost_nova.unlocked == false.
	_setup(2)
	var ok: bool = _manager.unlock("frost_nova")
	assert_false(ok, "prereq gate rejects unlock")
	assert_false(_tree.find("frost_nova").unlocked)
	assert_eq(_character.skill_points, 2, "no points consumed on rejected unlock")

func test_unlock_blocked_by_insufficient_points():
	# Issue test 3: zero available points -> fail, no tree mutation.
	_setup(0)
	var ok: bool = _manager.unlock("fireball")
	assert_false(ok, "zero points fails the unlock")
	assert_false(_tree.find("fireball").unlocked)
	assert_eq(_character.skill_points, 0, "skill point count unchanged")

func test_skill_tree_persistence_round_trip():
	# Issue test 4: a tree with fireball unlocked serializes and deserializes
	# with fireball.unlocked still true.
	_setup(1)
	_manager.unlock("fireball")
	assert_true(_tree.find("fireball").unlocked)

	var err := SaveManager.save(_character, TMP_PATH, _tree)
	assert_eq(err, OK)

	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.unlocked_skill_ids.size(), 1, "exactly one unlocked id saved")
	assert_true(loaded.unlocked_skill_ids.has("fireball"), "fireball id present in saved set")

	# Re-hydrate into a fresh tree and verify the unlocked flag is restored.
	var restored_tree := SkillTree.make_mage_tree()
	restored_tree.apply_unlocked_ids(loaded.unlocked_skill_ids)
	assert_true(restored_tree.find("fireball").unlocked, "fireball.unlocked survives round-trip")
	assert_false(restored_tree.find("frost_nova").unlocked, "locked nodes stay locked across round-trip")

func test_spell_cooldown_blocks_repeat_cast():
	# Issue test 5: casting a spell sets cooldown_remaining > 0; casting again
	# before it expires has no effect.
	var fireball := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	assert_true(fireball.is_ready(), "fresh spell starts ready")

	var first := fireball.cast()
	assert_true(first, "first cast fires")
	assert_gt(fireball.cooldown_remaining, 0.0, "cooldown_remaining set after cast")

	var second := fireball.cast()
	assert_false(second, "re-cast within cooldown is rejected")
	# Re-casts must not extend or reset cooldown — cooldown_remaining stays at
	# the post-first-cast value (modulo no tick).
	assert_eq(fireball.cooldown_remaining, fireball.cooldown, "cooldown unchanged on rejected cast")

	# After enough tick to drain the cooldown, the spell becomes ready again.
	fireball.tick(fireball.cooldown)
	assert_true(fireball.is_ready())
	assert_true(fireball.cast(), "post-cooldown cast succeeds")

# --- Coverage extras ---

func test_unlock_chain_after_prerequisite():
	# Sanity: with prereq satisfied, the gated node unlocks.
	_setup(2)
	assert_true(_manager.unlock("fireball"))
	assert_true(_manager.unlock("frost_nova"), "frost_nova unlocks once fireball is in")
	assert_eq(_character.skill_points, 0)

func test_double_unlock_is_noop():
	# Once a node is unlocked, a second unlock attempt should fail without
	# burning more points.
	_setup(2)
	assert_true(_manager.unlock("fireball"))
	assert_false(_manager.unlock("fireball"), "already-unlocked node rejects re-unlock")
	assert_eq(_character.skill_points, 1, "no extra point consumed on re-unlock attempt")

func test_unknown_node_id_is_rejected():
	_setup(5)
	assert_false(_manager.unlock("not_a_real_spell"))
	assert_eq(_character.skill_points, 5)

func test_progression_awards_skill_point_on_level_up():
	# Skill points come from leveling: 3 per level-up in the first tier.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.skill_points, 0, "starts with no points")
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(c.level, 2)
	assert_eq(c.skill_points, 3, "+3 skill points per level-up in tier 1 (L1-10)")

func test_progression_skill_points_accumulate_across_levels():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	# L1->L4 with 3 xp remaining: thresholds 1+2+3 then +3.
	var total: int = ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) \
		+ ProgressionSystem.xp_to_next_level(3) + 3
	ProgressionSystem.add_xp(c, total)
	assert_eq(c.level, 4)
	assert_eq(c.skill_points, 9, "3 levels * 3 points/level in tier 1")

func test_save_layer_preserves_skill_points():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 4
	var tree := SkillTree.make_mage_tree()
	SaveManager.save(c, TMP_PATH, tree)
	var loaded := SaveManager.load(TMP_PATH)
	assert_eq(loaded.skill_points, 4)

func test_get_unlocked_spells_returns_only_unlocked():
	_setup(2)
	assert_eq(_tree.get_unlocked_spells().size(), 0, "fresh tree has no unlocked spells")
	_manager.unlock("fireball")
	var spells: Array = _tree.get_unlocked_spells()
	assert_eq(spells.size(), 1)
	var first: Spell = spells[0]
	assert_eq(first.id, "fireball")

func test_spell_kinds_are_distinct_for_mage_tree():
	# Acceptance criterion: each spell has a distinct effect (damage/area/buff).
	var t := SkillTree.make_mage_tree()
	var fireball := t.find("fireball").spell
	var frost_nova := t.find("frost_nova").spell
	var arcane_surge := t.find("arcane_surge").spell
	assert_eq(fireball.effect_kind, Spell.EffectKind.DAMAGE)
	assert_eq(frost_nova.effect_kind, Spell.EffectKind.AREA)
	assert_eq(arcane_surge.effect_kind, Spell.EffectKind.BUFF)

func test_spell_effect_resolver_damage_hits_first_alive_target():
	var fireball := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	# PRD #85: caster.magic_attack now adds to spell.power. Pin to 0 so the
	# test stays focused on the "first target only" contract.
	var caster := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	caster.magic_attack = 0
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var e1_hp_before := e1.hp
	var e2_hp_before := e2.hp
	var dealt := SpellEffectResolver.apply(fireball, caster, [e1, e2])
	assert_eq(dealt, 3, "single-target damage applied once")
	assert_lt(e1.hp, e1_hp_before, "first target took damage")
	assert_eq(e2.hp, e2_hp_before, "second target untouched by single-target spell")

func test_spell_effect_resolver_area_hits_all_alive_targets():
	var nova := Spell.make("frost_nova", "Frost Nova", Spell.EffectKind.AREA, 2, 1.5)
	var caster := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.BAT)
	var e1_hp_before := e1.hp
	var e2_hp_before := e2.hp
	SpellEffectResolver.apply(nova, caster, [e1, e2])
	assert_lt(e1.hp, e1_hp_before, "area spell hits first target")
	assert_lt(e2.hp, e2_hp_before, "area spell hits second target")
