class_name ItemDisplayFormatter
extends RefCounted

# Pure, node-free formatter. Single source of truth for how an ItemData
# breaks down into display pieces. See PRD #292 / Slice #293.

const RARITY_LABELS := {
	ItemData.Rarity.COMMON: "Common",
	ItemData.Rarity.RARE: "Rare",
	ItemData.Rarity.EPIC: "Epic",
}

# Match the existing border colors in EquipmentTabPanel._RARITY_COLORS so the
# rarity tint stays consistent with equipped-tile borders.
const RARITY_COLORS := {
	ItemData.Rarity.COMMON: Color(0.72, 0.74, 0.78, 0.95),
	ItemData.Rarity.RARE: Color(0.36, 0.56, 0.95, 0.95),
	ItemData.Rarity.EPIC: Color(0.74, 0.42, 0.96, 0.95),
}

const STAT_LABELS := {
	"attack": "Attack",
	"magic_attack": "Magic Attack",
	"defense": "Defense",
	"magic_resistance": "Magic Resistance",
	"luck": "Luck",
	"evasion": "Evasion",
	"crit_chance": "Crit Chance",
	"max_hp": "Max HP",
	"max_mp": "Max MP",
	"mp_regen": "MP Regen",
	"regeneration": "Regeneration",
	"speed": "Speed",
}

static func display_name(item: ItemData) -> String:
	return item.display_name

static func rarity_label(item: ItemData) -> String:
	return RARITY_LABELS.get(item.rarity, "Common")

static func rarity_color(item: ItemData) -> Color:
	return RARITY_COLORS.get(item.rarity, RARITY_COLORS[ItemData.Rarity.COMMON])

static func bonus_lines(item: ItemData) -> Array[String]:
	var lines: Array[String] = []
	for bonus in item.bonuses:
		if bonus == null or bonus.stat_name == "":
			continue
		lines.append(_format_bonus(bonus))
	return lines

static func _format_bonus(bonus: StatBonus) -> String:
	var formatted: String
	if bonus.stat_bonus == int(bonus.stat_bonus):
		formatted = "+%d" % int(bonus.stat_bonus)
	else:
		formatted = "+%.2f" % bonus.stat_bonus
	return "%s %s" % [formatted, _humanize_stat(bonus.stat_name)]

static func _humanize_stat(stat_name: String) -> String:
	if STAT_LABELS.has(stat_name):
		return STAT_LABELS[stat_name]
	var parts := stat_name.split("_")
	var out := PackedStringArray()
	for p in parts:
		if p == "":
			continue
		out.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(out)
