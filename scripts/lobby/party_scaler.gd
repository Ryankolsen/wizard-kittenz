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

# Returns a NEW CharacterData scaled to the floor level. Base combat resources
# (hp, attack, defense, speed, magic_attack, max_mp) are set to the floor-level
# class baseline. Earned secondary stats (crit_chance, evasion, luck, etc.) carry
# through — they add fun without removing challenge. xp / skill_points /
# character_name also carry so scaling isn't a progression rollback. If the input
# is at or below the floor, returns a plain clone — no spurious downgrades.
static func scale_stats(stats: CharacterData, floor_level: int) -> CharacterData:
	if stats == null:
		return null
	if stats.level <= floor_level:
		return stats.clone()
	# Clone-then-override: carry earned secondary stats (crit, evasion, luck,
	# etc.) but stomp base combat resources with floor-level values so the
	# session is challenging even for high-level players.
	var c := stats.clone()
	c.level = floor_level
	c.max_hp = CharacterData.base_max_hp_for(stats.character_class, floor_level)
	c.hp = c.max_hp
	c.attack = CharacterData.base_attack_for(stats.character_class, floor_level)
	c.defense = CharacterData.base_defense_for(stats.character_class, floor_level)
	c.speed = CharacterData.base_speed_for(stats.character_class, floor_level)
	c.magic_attack = CharacterData.base_magic_attack_for(stats.character_class, floor_level)
	c.max_mp = CharacterData.base_max_mp_for(stats.character_class, floor_level)
	c.magic_points = c.max_mp
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
	return stats.clone()
