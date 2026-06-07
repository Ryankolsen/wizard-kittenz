class_name SkillCategory
extends RefCounted

# PRD #353, slice 1 (issue #354). Single source of truth for the 3-category
# color language shared by the Skills menu and the quickbar HUD. Maps each
# Spell.EffectKind into one of {ATTACK, HEALING, PROTECT} and exposes the
# canonical color and label per category. Locked / unavailable rows use the
# neutral gray LOCKED color regardless of category.

enum Category { ATTACK, HEALING, PROTECT }

const COLOR_ATTACK := Color(0.85, 0.25, 0.25)
const COLOR_HEALING := Color(0.30, 0.55, 0.95)
const COLOR_PROTECT := Color(0.30, 0.80, 0.40)
const COLOR_LOCKED := Color(0.55, 0.55, 0.60)

static func category_for_kind(kind: int) -> Category:
	match kind:
		Spell.EffectKind.DAMAGE, Spell.EffectKind.AREA:
			return Category.ATTACK
		Spell.EffectKind.HEAL, Spell.EffectKind.SMART_HEAL, Spell.EffectKind.AOE_HEAL, Spell.EffectKind.GROUP_REGEN:
			return Category.HEALING
		Spell.EffectKind.BUFF, Spell.EffectKind.PARTY_BUFF, Spell.EffectKind.TAUNT:
			return Category.PROTECT
		_:
			return Category.ATTACK

static func color_for_category(category: Category) -> Color:
	match category:
		Category.ATTACK:
			return COLOR_ATTACK
		Category.HEALING:
			return COLOR_HEALING
		Category.PROTECT:
			return COLOR_PROTECT
		_:
			return COLOR_ATTACK

static func label_for_category(category: Category) -> String:
	match category:
		Category.ATTACK:
			return "Attack"
		Category.HEALING:
			return "Healing"
		Category.PROTECT:
			return "Protect"
		_:
			return "Attack"

static func color_for_kind(kind: int) -> Color:
	return color_for_category(category_for_kind(kind))

# PRD #353, slice 2 (issue #355). Returns the {dot, name} colors a Skills
# menu row should paint for a given unlocked-state + spell. Locked rows and
# unlocked passive nodes (no spell to categorize) collapse to LOCKED gray so
# the color exclusively signals "a categorized skill I can actually use."
static func row_colors(unlocked: bool, spell: Spell) -> Dictionary:
	if not unlocked or spell == null:
		return { "dot": COLOR_LOCKED, "name": COLOR_LOCKED }
	var c := color_for_kind(spell.effect_kind)
	return { "dot": c, "name": c }
