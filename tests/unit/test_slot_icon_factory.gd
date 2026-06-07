extends GutTest

# Slice 3 of PRD #210. SlotIconFactory builds a placeholder Texture2D for a
# Quickbar slot — colored disc keyed off Spell.effect_kind with the spell
# name's first letter overlaid. Real art can swap in later by introducing
# Spell.icon and falling back to the factory when null.
#
# Per PRD #353, color_for_kind now delegates to SkillCategory.

func _spell(id: String, name: String, kind: int) -> Spell:
	return Spell.make(id, name, kind, 1, 1.0, 0, 0)

func test_make_icon_returns_texture():
	var s := _spell("hairball_hex", "Hairball Hex", Spell.EffectKind.DAMAGE)
	var tex := SlotIconFactory.make_icon(s)
	assert_not_null(tex, "make_icon must return a Texture2D")
	assert_true(tex is Texture2D, "result must be Texture2D")

func test_color_delegates_to_skill_category():
	# Every EffectKind goes through SkillCategory so menu dots and HUD
	# circles can never disagree.
	var kinds := [
		Spell.EffectKind.DAMAGE,
		Spell.EffectKind.AREA,
		Spell.EffectKind.HEAL,
		Spell.EffectKind.SMART_HEAL,
		Spell.EffectKind.AOE_HEAL,
		Spell.EffectKind.GROUP_REGEN,
		Spell.EffectKind.BUFF,
		Spell.EffectKind.PARTY_BUFF,
		Spell.EffectKind.TAUNT,
	]
	for k in kinds:
		assert_eq(SlotIconFactory.color_for_kind(k), SkillCategory.color_for_kind(k))

func test_letter_uses_first_char_of_display_name():
	assert_eq(SlotIconFactory.letter_for_spell(
		_spell("hairball_hex", "Hairball Hex", Spell.EffectKind.DAMAGE)), "H")
	assert_eq(SlotIconFactory.letter_for_spell(
		_spell("catnip_curse", "Catnip Curse", Spell.EffectKind.DAMAGE)), "C")
	assert_eq(SlotIconFactory.letter_for_spell(null), "")
