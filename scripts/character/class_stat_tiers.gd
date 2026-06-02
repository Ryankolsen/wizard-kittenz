class_name ClassStatTiers
extends RefCounted

# Per-class stat tier table (PRD #316 / issue #317). Single source of truth
# for which stats a class can allocate via skill points, what each point
# costs, and how many points it can stack. Items bypass these caps and are
# applied by ItemStatApplicator regardless of tier.

enum Tier { PRIMARY, SECONDARY, OFF_STAT, FORBIDDEN }

# Sentinel "no cap" return for Primary stats. Larger than any plausible
# point investment so callers can use plain `> get_cap()` checks without
# special-casing PRIMARY.
const PRIMARY_UNCAPPED := 2147483647
const SECONDARY_CAP := 10
const OFF_STAT_CAP := 3
# Sleepy's regeneration is Primary but has the only explicit Primary cap
# in the PRD (+5). Encoded as a special-case at lookup time.
const SLEEPY_REGEN_CAP := 5

# Tier table keyed by Kitten-tier class. Cat-tier classes share the same
# archetype tiers (see _archetype_class_for). Encoded as a flat dictionary
# of {stat_name: Tier} per class for cheap O(1) lookup.
const _TIERS_BY_ARCHETYPE := {
	CharacterData.CharacterClass.BATTLE_KITTEN: {
		"max_hp": Tier.SECONDARY,
		"max_mp": Tier.OFF_STAT,
		"attack": Tier.PRIMARY,
		"magic_attack": Tier.OFF_STAT,
		"defense": Tier.SECONDARY,
		"magic_resistance": Tier.OFF_STAT,
		"speed": Tier.SECONDARY,
		"dexterity": Tier.PRIMARY,
		"evasion": Tier.SECONDARY,
		"crit_chance": Tier.PRIMARY,
		"luck": Tier.SECONDARY,
		"regeneration": Tier.OFF_STAT,
		"mp_regen": Tier.FORBIDDEN,
	},
	CharacterData.CharacterClass.WIZARD_KITTEN: {
		"max_hp": Tier.OFF_STAT,
		"max_mp": Tier.PRIMARY,
		"attack": Tier.FORBIDDEN,
		"magic_attack": Tier.PRIMARY,
		"defense": Tier.OFF_STAT,
		"magic_resistance": Tier.SECONDARY,
		"speed": Tier.SECONDARY,
		"dexterity": Tier.OFF_STAT,
		"evasion": Tier.OFF_STAT,
		"crit_chance": Tier.SECONDARY,
		"luck": Tier.SECONDARY,
		"regeneration": Tier.OFF_STAT,
		"mp_regen": Tier.SECONDARY,
	},
	CharacterData.CharacterClass.SLEEPY_KITTEN: {
		"max_hp": Tier.SECONDARY,
		"max_mp": Tier.PRIMARY,
		"attack": Tier.OFF_STAT,
		"magic_attack": Tier.SECONDARY,
		"defense": Tier.OFF_STAT,
		"magic_resistance": Tier.SECONDARY,
		"speed": Tier.OFF_STAT,
		"dexterity": Tier.OFF_STAT,
		"evasion": Tier.OFF_STAT,
		"crit_chance": Tier.OFF_STAT,
		"luck": Tier.SECONDARY,
		"regeneration": Tier.PRIMARY,
		"mp_regen": Tier.PRIMARY,
	},
	CharacterData.CharacterClass.CHONK_KITTEN: {
		"max_hp": Tier.PRIMARY,
		"max_mp": Tier.FORBIDDEN,
		"attack": Tier.SECONDARY,
		"magic_attack": Tier.FORBIDDEN,
		"defense": Tier.PRIMARY,
		"magic_resistance": Tier.SECONDARY,
		"speed": Tier.OFF_STAT,
		"dexterity": Tier.SECONDARY,
		"evasion": Tier.FORBIDDEN,
		"crit_chance": Tier.OFF_STAT,
		"luck": Tier.OFF_STAT,
		"regeneration": Tier.SECONDARY,
		"mp_regen": Tier.FORBIDDEN,
	},
}

# Map any class (Kitten or Cat) to its Kitten archetype so the tier table
# is authored in one place. Cat tiers inherit Kitten tiers per PRD #316
# "Out of Scope" notes.
static func _archetype_class_for(klass: int) -> int:
	match klass:
		CharacterData.CharacterClass.BATTLE_CAT: return CharacterData.CharacterClass.BATTLE_KITTEN
		CharacterData.CharacterClass.WIZARD_CAT: return CharacterData.CharacterClass.WIZARD_KITTEN
		CharacterData.CharacterClass.SLEEPY_CAT: return CharacterData.CharacterClass.SLEEPY_KITTEN
		CharacterData.CharacterClass.CHONK_CAT: return CharacterData.CharacterClass.CHONK_KITTEN
	return klass

# Returns the Tier for (class, stat). Unknown stats return FORBIDDEN so a
# typo in a plan or UI binding fails closed rather than silently allowing
# allocation under default rules.
static func get_tier(klass: int, stat: String) -> Tier:
	var archetype := _archetype_class_for(klass)
	var table: Dictionary = _TIERS_BY_ARCHETYPE.get(archetype, {})
	return table.get(stat, Tier.FORBIDDEN)

# SP cost per allocated point. PRIMARY/SECONDARY = 1, OFF_STAT = 2,
# FORBIDDEN = 0 (caller should reject before charging).
static func get_sp_cost(klass: int, stat: String) -> int:
	match get_tier(klass, stat):
		Tier.PRIMARY: return 1
		Tier.SECONDARY: return 1
		Tier.OFF_STAT: return 2
	return 0

# Max allocated points for (class, stat). Sleepy regeneration is the only
# capped Primary (per PRD); all other Primary stats return PRIMARY_UNCAPPED.
static func get_cap(klass: int, stat: String) -> int:
	var archetype := _archetype_class_for(klass)
	var tier := get_tier(klass, stat)
	match tier:
		Tier.PRIMARY:
			if archetype == CharacterData.CharacterClass.SLEEPY_KITTEN and stat == "regeneration":
				return SLEEPY_REGEN_CAP
			return PRIMARY_UNCAPPED
		Tier.SECONDARY: return SECONDARY_CAP
		Tier.OFF_STAT: return OFF_STAT_CAP
	return 0
