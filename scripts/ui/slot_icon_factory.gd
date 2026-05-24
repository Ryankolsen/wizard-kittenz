class_name SlotIconFactory
extends RefCounted

# Slice 3 of PRD #210. Builds a placeholder icon Texture2D for a Quickbar
# slot — a colored disc keyed off Spell.effect_kind with the spell name's
# first letter overlaid as a marker. Real art can replace this later by
# introducing Spell.icon and falling back to make_icon when null.
#
# Pure helper: no scene, no node — just CPU pixel math returning an
# ImageTexture. Color mapping + letter selection are exposed as separate
# static helpers so unit tests can assert on the mapping table without
# decoding rendered pixels.

const COLOR_DAMAGE := Color(0.85, 0.25, 0.25)
const COLOR_HEAL := Color(0.30, 0.85, 0.40)
const COLOR_BUFF := Color(0.95, 0.85, 0.30)
const COLOR_AREA := Color(0.95, 0.55, 0.20)
const COLOR_TAUNT := Color(0.60, 0.60, 0.65)
const COLOR_DEFAULT := Color(0.55, 0.30, 0.80)

const ICON_SIZE: int = 32

static func color_for_kind(kind: int) -> Color:
	match kind:
		Spell.EffectKind.DAMAGE:
			return COLOR_DAMAGE
		Spell.EffectKind.HEAL, Spell.EffectKind.SMART_HEAL, Spell.EffectKind.AOE_HEAL, Spell.EffectKind.GROUP_REGEN:
			return COLOR_HEAL
		Spell.EffectKind.BUFF, Spell.EffectKind.PARTY_BUFF:
			return COLOR_BUFF
		Spell.EffectKind.AREA:
			return COLOR_AREA
		Spell.EffectKind.TAUNT:
			return COLOR_TAUNT
		_:
			return COLOR_DEFAULT

static func letter_for_spell(spell: Spell) -> String:
	if spell == null or spell.display_name == "":
		return ""
	return spell.display_name.substr(0, 1).to_upper()

static func make_icon(spell: Spell) -> Texture2D:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color := COLOR_DEFAULT if spell == null else color_for_kind(spell.effect_kind)
	var center := Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	var radius := float(ICON_SIZE) * 0.45
	for y in range(ICON_SIZE):
		for x in range(ICON_SIZE):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
