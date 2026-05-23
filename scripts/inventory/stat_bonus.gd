class_name StatBonus
extends Resource

@export var stat_name: String = ""
@export var stat_bonus: float = 0.0

static func make(p_stat_name: String, p_stat_bonus: float) -> StatBonus:
	var b := StatBonus.new()
	b.stat_name = p_stat_name
	b.stat_bonus = p_stat_bonus
	return b
