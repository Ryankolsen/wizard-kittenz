class_name SlotIconFactory
extends RefCounted

# Slice 3 of PRD #210. Builds a placeholder icon Texture2D for a Quickbar
# slot — a colored disc keyed off Spell.effect_kind with the spell name's
# first letter overlaid as a marker. Real art can replace this later by
# introducing Spell.icon and falling back to make_icon when null.
#
# Color mapping delegates to SkillCategory (PRD #353) so menu dots and HUD
# circles share one palette.

const ICON_SIZE: int = 32

static func color_for_kind(kind: int) -> Color:
	return SkillCategory.color_for_kind(kind)

static func letter_for_spell(spell: Spell) -> String:
	if spell == null or spell.display_name == "":
		return ""
	return spell.display_name.substr(0, 1).to_upper()

static func make_icon(spell: Spell) -> Texture2D:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color := SkillCategory.COLOR_ATTACK if spell == null else color_for_kind(spell.effect_kind)
	var center := Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	var radius := float(ICON_SIZE) * 0.45
	for y in range(ICON_SIZE):
		for x in range(ICON_SIZE):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
