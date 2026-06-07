extends GutTest

# PRD #353, slice 1 (issue #354). SkillCategory is the single source of truth
# mapping a Spell.EffectKind into one of {ATTACK, HEALING, PROTECT} with a
# canonical color + label per category. The Skills menu and quickbar HUD both
# read from this module so they can never disagree.

func test_damage_bucketed_as_attack():
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.DAMAGE),
		SkillCategory.Category.ATTACK)

func test_full_bucketing():
	# ATTACK
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.DAMAGE),
		SkillCategory.Category.ATTACK)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.AREA),
		SkillCategory.Category.ATTACK)
	# HEALING
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.HEAL),
		SkillCategory.Category.HEALING)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.SMART_HEAL),
		SkillCategory.Category.HEALING)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.AOE_HEAL),
		SkillCategory.Category.HEALING)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.GROUP_REGEN),
		SkillCategory.Category.HEALING)
	# PROTECT
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.BUFF),
		SkillCategory.Category.PROTECT)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.PARTY_BUFF),
		SkillCategory.Category.PROTECT)
	assert_eq(SkillCategory.category_for_kind(Spell.EffectKind.TAUNT),
		SkillCategory.Category.PROTECT)

func test_category_colors():
	assert_eq(SkillCategory.color_for_category(SkillCategory.Category.ATTACK),
		SkillCategory.COLOR_ATTACK)
	assert_eq(SkillCategory.color_for_category(SkillCategory.Category.HEALING),
		SkillCategory.COLOR_HEALING)
	assert_eq(SkillCategory.color_for_category(SkillCategory.Category.PROTECT),
		SkillCategory.COLOR_PROTECT)

func test_category_colors_are_mutually_distinct():
	assert_ne(SkillCategory.COLOR_ATTACK, SkillCategory.COLOR_HEALING)
	assert_ne(SkillCategory.COLOR_ATTACK, SkillCategory.COLOR_PROTECT)
	assert_ne(SkillCategory.COLOR_HEALING, SkillCategory.COLOR_PROTECT)

func test_category_labels():
	assert_eq(SkillCategory.label_for_category(SkillCategory.Category.ATTACK), "Attack")
	assert_eq(SkillCategory.label_for_category(SkillCategory.Category.HEALING), "Healing")
	assert_eq(SkillCategory.label_for_category(SkillCategory.Category.PROTECT), "Protect")

func test_locked_color_exists_and_is_distinct():
	assert_ne(SkillCategory.COLOR_LOCKED, SkillCategory.COLOR_ATTACK)
	assert_ne(SkillCategory.COLOR_LOCKED, SkillCategory.COLOR_HEALING)
	assert_ne(SkillCategory.COLOR_LOCKED, SkillCategory.COLOR_PROTECT)

func test_color_for_kind_composes_with_category():
	assert_eq(SkillCategory.color_for_kind(Spell.EffectKind.HEAL),
		SkillCategory.color_for_category(SkillCategory.Category.HEALING))
	assert_eq(SkillCategory.color_for_kind(Spell.EffectKind.DAMAGE),
		SkillCategory.color_for_category(SkillCategory.Category.ATTACK))
	assert_eq(SkillCategory.color_for_kind(Spell.EffectKind.TAUNT),
		SkillCategory.color_for_category(SkillCategory.Category.PROTECT))

func test_row_colors_locked_uses_gray_for_both():
	# Slice 2 (#355): locked rows surface LOCKED gray for both the dot and
	# the name tint so color exclusively signals "usable" skills.
	var spell := Spell.make("x", "X", Spell.EffectKind.HEAL, 1, 1.0)
	var colors := SkillCategory.row_colors(false, spell)
	assert_eq(colors["dot"], SkillCategory.COLOR_LOCKED)
	assert_eq(colors["name"], SkillCategory.COLOR_LOCKED)

func test_row_colors_unlocked_categorized_by_spell():
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 1, 1.0)
	var colors := SkillCategory.row_colors(true, spell)
	assert_eq(colors["dot"], SkillCategory.COLOR_HEALING)
	assert_eq(colors["name"], SkillCategory.COLOR_HEALING)
	var atk := Spell.make("a", "Atk", Spell.EffectKind.DAMAGE, 1, 1.0)
	var atk_colors := SkillCategory.row_colors(true, atk)
	assert_eq(atk_colors["dot"], SkillCategory.COLOR_ATTACK)
	var taunt := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	var taunt_colors := SkillCategory.row_colors(true, taunt)
	assert_eq(taunt_colors["dot"], SkillCategory.COLOR_PROTECT)

func test_row_colors_unlocked_passive_no_spell_uses_gray():
	# A passive unlocked node with no spell has no kind to categorize, so
	# fall back to LOCKED gray rather than mis-labeling it as ATTACK.
	var colors := SkillCategory.row_colors(true, null)
	assert_eq(colors["dot"], SkillCategory.COLOR_LOCKED)
	assert_eq(colors["name"], SkillCategory.COLOR_LOCKED)

func test_unknown_kind_falls_back_to_attack():
	# Defined fallback so an out-of-range int can't crash callers. ATTACK is
	# the most common category and the safest visual default.
	assert_eq(SkillCategory.category_for_kind(999), SkillCategory.Category.ATTACK)
	assert_eq(SkillCategory.category_for_kind(-1), SkillCategory.Category.ATTACK)
