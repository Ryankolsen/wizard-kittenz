class_name ProgressionSystem
extends RefCounted

# Soft power XP curve: floor(XP_BASE * level^1.5). XP_BASE is the single
# tuning knob — flip this constant to globally scale early-vs-late pacing
# without touching the formula.
const XP_BASE := 100

# Gems awarded each time a character gains a level. Small constant so leveling
# steadily drips a premium-currency reward without overlapping with the much
# larger Gem grants from chests / IAP. Tunes in the QA pass (#72).
const LEVEL_UP_GEM_REWARD := 3

# XP required to advance from `level` to `level + 1`.
static func xp_to_next_level(level: int) -> int:
	if level <= 0:
		return XP_BASE
	return floori(float(XP_BASE) * pow(float(level), 1.5))

# Adds XP to the character, applying any level-ups that the new total triggers.
# Returns the number of levels gained. Negative or zero amounts are a no-op so
# kill rewards from a future debuff/penalty system can't drive xp below zero.
static func add_xp(c: CharacterData, amount: int, ledger: CurrencyLedger = null) -> int:
	if amount <= 0:
		return 0
	c.xp += amount
	var levels_gained := 0
	while c.xp >= xp_to_next_level(c.level):
		c.xp -= xp_to_next_level(c.level)
		c.level += 1
		levels_gained += 1
		_apply_level_up(c, ledger)
	return levels_gained

# Stat points awarded for reaching `level`. Scales every 10 levels:
# Levels 1-10 award 3, 11-20 award 4, 21-30 award 5, etc. The "level"
# argument is the post-increment level (the level just achieved).
static func stat_points_for_level(level: int) -> int:
	return 3 + (maxi(1, level) - 1) / 10

static func _apply_level_up(c: CharacterData, ledger: CurrencyLedger = null) -> void:
	var new_max_hp := CharacterData.base_max_hp_for(c.character_class, c.level)
	var hp_gain := new_max_hp - c.max_hp
	c.max_hp = new_max_hp
	c.hp = mini(c.hp + hp_gain, c.max_hp)
	c.skill_points += stat_points_for_level(c.level)
	if ledger != null:
		ledger.credit(LEVEL_UP_GEM_REWARD, CurrencyLedger.Currency.GEM)
