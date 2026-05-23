class_name ItemData
extends Resource

enum Slot { WEAPON, ARMOR, ACCESSORY }
enum Rarity { COMMON, RARE, EPIC }

@export var id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var bonuses: Array[StatBonus] = []

static func make(p_id: String, p_display_name: String, p_slot: Slot, p_rarity: Rarity, p_stat_name: String, p_stat_bonus: float) -> ItemData:
	return make_multi(p_id, p_display_name, p_slot, p_rarity, [StatBonus.make(p_stat_name, p_stat_bonus)])

static func make_multi(p_id: String, p_display_name: String, p_slot: Slot, p_rarity: Rarity, p_bonuses: Array) -> ItemData:
	var d := ItemData.new()
	d.id = p_id
	d.display_name = p_display_name
	d.slot = p_slot
	d.rarity = p_rarity
	var typed: Array[StatBonus] = []
	for b in p_bonuses:
		typed.append(b)
	d.bonuses = typed
	return d
