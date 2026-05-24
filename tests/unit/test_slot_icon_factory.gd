extends GutTest

# Slice 3 of PRD #210. SlotIconFactory builds a placeholder Texture2D for a
# Quickbar slot — colored disc keyed off Spell.effect_kind with the spell
# name's first letter overlaid. Real art can swap in later by introducing
# Spell.icon and falling back to the factory when null.

func _spell(id: String, name: String, kind: int) -> Spell:
	return Spell.make(id, name, kind, 1, 1.0, 0, 0)

func test_make_icon_returns_texture():
	var s := _spell("hairball_hex", "Hairball Hex", Spell.EffectKind.DAMAGE)
	var tex := SlotIconFactory.make_icon(s)
	assert_not_null(tex, "make_icon must return a Texture2D")
	assert_true(tex is Texture2D, "result must be Texture2D")

func test_color_matches_effect_kind():
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.DAMAGE), SlotIconFactory.COLOR_DAMAGE)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.HEAL), SlotIconFactory.COLOR_HEAL)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.SMART_HEAL), SlotIconFactory.COLOR_HEAL)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.AOE_HEAL), SlotIconFactory.COLOR_HEAL)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.GROUP_REGEN), SlotIconFactory.COLOR_HEAL)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.BUFF), SlotIconFactory.COLOR_BUFF)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.PARTY_BUFF), SlotIconFactory.COLOR_BUFF)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.AREA), SlotIconFactory.COLOR_AREA)
	assert_eq(SlotIconFactory.color_for_kind(Spell.EffectKind.TAUNT), SlotIconFactory.COLOR_TAUNT)
	assert_eq(SlotIconFactory.color_for_kind(-1), SlotIconFactory.COLOR_DEFAULT,
		"unknown kind falls back to default color")

func test_letter_uses_first_char_of_display_name():
	assert_eq(SlotIconFactory.letter_for_spell(
		_spell("hairball_hex", "Hairball Hex", Spell.EffectKind.DAMAGE)), "H")
	assert_eq(SlotIconFactory.letter_for_spell(
		_spell("catnip_curse", "Catnip Curse", Spell.EffectKind.DAMAGE)), "C")
	assert_eq(SlotIconFactory.letter_for_spell(null), "")
