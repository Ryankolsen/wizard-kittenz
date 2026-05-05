class_name PartyScaler
extends RefCounted

# Returns the lowest level in the party. Empty array yields 1 — the safe
# floor for a freshly-created character so a degenerate "party of zero"
# never produces nonsense (negative / out-of-bounds level lookups).
static func compute_floor(levels: Array) -> int:
	if levels.is_empty():
		return 1
	var floor_level: int = int(levels[0])
	for raw in levels:
		var lvl := int(raw)
		if lvl < floor_level:
			floor_level = lvl
	return floor_level

# Returns a NEW CharacterData with stats matching the floor level for the
# same class. xp / skill_points / character_name carry over so a scaled
# session doesn't cosmetically reset the player. If the input is at or
# below the floor (the floor player itself), the returned clone has stats
# identical to the input — scale factor 1.0, no spurious downgrades.
static func scale_stats(stats: CharacterData, floor_level: int) -> CharacterData:
	if stats == null:
		return null
	if stats.level <= floor_level:
		return clone_stats(stats)
	var c := CharacterData.new()
	c.character_name = stats.character_name
	c.character_class = stats.character_class
	c.level = floor_level
	c.xp = stats.xp
	c.max_hp = CharacterData.base_max_hp_for(stats.character_class, floor_level)
	c.hp = c.max_hp
	c.attack = CharacterData.base_attack_for(stats.character_class, floor_level)
	c.defense = CharacterData.base_defense_for(stats.character_class, floor_level)
	c.speed = CharacterData.base_speed_for(stats.character_class, floor_level)
	c.skill_points = stats.skill_points
	c.facing = stats.facing
	return c

# Restores effective_stats to mirror real_stats. Inverse of applying
# scale_stats — used on session end to drop the temporary scaled view.
# Duck-typed: anything with real_stats and effective_stats fields works.
static func remove_scaling(player) -> void:
	player.effective_stats = clone_stats(player.real_stats)

# HUD label: "Lv.10 (Lv.3)" while scaled, "Lv.10" when stats match.
static func format_hud_level(player) -> String:
	if player.real_stats.level == player.effective_stats.level:
		return "Lv.%d" % player.real_stats.level
	return "Lv.%d (Lv.%d)" % [player.real_stats.level, player.effective_stats.level]

# Public so PartyMember and tests can mint a fresh CharacterData copy
# without reaching for Resource.duplicate() (which doesn't preserve
# non-@export'd fields like `facing`).
static func clone_stats(stats: CharacterData) -> CharacterData:
	var c := CharacterData.new()
	c.character_name = stats.character_name
	c.character_class = stats.character_class
	c.level = stats.level
	c.xp = stats.xp
	c.hp = stats.hp
	c.max_hp = stats.max_hp
	c.attack = stats.attack
	c.defense = stats.defense
	c.speed = stats.speed
	c.skill_points = stats.skill_points
	c.facing = stats.facing
	return c
