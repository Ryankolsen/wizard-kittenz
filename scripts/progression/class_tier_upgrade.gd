class_name ClassTierUpgrade
extends RefCounted

# Upgrades an existing Kitten class to its matching Cat tier (e.g. Battle
# Kitten -> Battle Cat). The
# transformation preserves *progression* (level, xp, skill_points,
# unlocked_skill_ids) — those are the things the player worked for. Stats are
# recomputed from the upgraded class's per-level baselines so the upgrade
# actually delivers the "improved base stats" promised in the issue.
#
# Stateless: the upgrade is a pure mutation on a CharacterData ref. The mapping
# of base->tier lives in TIER_MAP so adding a new tier is a one-line dictionary
# update — same data-driven seam UnlockRegistry uses for unlock conditions.

const TIER_MAP: Dictionary = {
	CharacterData.CharacterClass.BATTLE_KITTEN: CharacterData.CharacterClass.BATTLE_CAT,
	CharacterData.CharacterClass.WIZARD_KITTEN: CharacterData.CharacterClass.WIZARD_CAT,
	CharacterData.CharacterClass.SLEEPY_KITTEN: CharacterData.CharacterClass.SLEEPY_CAT,
	CharacterData.CharacterClass.CHONK_KITTEN: CharacterData.CharacterClass.CHONK_CAT,
}

static func has_upgrade(klass: int) -> bool:
	return TIER_MAP.has(klass)

static func target_for(klass: int) -> int:
	return int(TIER_MAP.get(klass, klass))

# Upgrades `c` in place. Returns true on success, false when there's no
# registered tier upgrade for the character's current class. xp/level/
# skill_points are explicitly *not* touched — that's the "preserves
# progression" acceptance criterion. max_hp is recomputed from the upgraded
# class's curve and the character is healed up by the delta (matches the
# level-up heal semantics in ProgressionSystem).
static func upgrade(c: CharacterData) -> bool:
	if c == null:
		return false
	if not has_upgrade(c.character_class):
		return false
	var target_class: int = TIER_MAP[c.character_class]
	var preserved_xp := c.xp
	var preserved_level := c.level
	var preserved_skill_points := c.skill_points
	var hp_before := c.hp
	var max_before := c.max_hp

	c.character_class = target_class
	c.max_hp = CharacterData.base_max_hp_for(target_class, c.level)
	c.attack = CharacterData.base_attack_for(target_class, c.level)
	c.defense = CharacterData.base_defense_for(target_class, c.level)
	c.speed = CharacterData.base_speed_for(target_class, c.level)
	# Heal by the max_hp delta so the upgrade feels rewarding without trivially
	# full-restoring; identical to the level-up heal shape in ProgressionSystem.
	var hp_delta: int = c.max_hp - max_before
	c.hp = mini(hp_before + maxi(0, hp_delta), c.max_hp)

	c.xp = preserved_xp
	c.level = preserved_level
	c.skill_points = preserved_skill_points
	return true
