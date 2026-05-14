class_name ItemData
extends Resource

enum Slot { WEAPON, ARMOR, ACCESSORY }
enum Rarity { COMMON, RARE, EPIC }

@export var id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var stat_name: String = ""
@export var stat_bonus: float = 0.0

static func make(p_id: String, p_display_name: String, p_slot: Slot, p_rarity: Rarity, p_stat_name: String, p_stat_bonus: float) -> ItemData:
	var d := ItemData.new()
	d.id = p_id
	d.display_name = p_display_name
	d.slot = p_slot
	d.rarity = p_rarity
	d.stat_name = p_stat_name
	d.stat_bonus = p_stat_bonus
	return d
