class_name PartyLevelCap
extends RefCounted

# Slice 4 of PRD #322. Party level-cap "sync-down" transformation: a
# high-level player joining a lower-level party has their effective combat
# stats clamped down so the encounter still threatens them. Unlike
# PartyScaler (which floors stats to the party-min level), this caps to the
# decade boundary at-or-above the party min: a level-30 player joining a
# level-5 friend syncs to level 10, not level 5. The wider window lets the
# high-level player keep most of their spec while still feeling the bite.
#
# The cap function is item-blind: callers re-apply ItemStatApplicator on top
# of the result, so item bonuses pass through unchanged. The input character
# is expected to represent base + allocations only.

const CAP_GRANULARITY := 10

# ceil(min(party_levels) / 10) * 10. Decade boundaries map to themselves
# (level 10 -> 10, not 20) so a party of two level-10 players doesn't get
# stranded one decade above where they actually are. Empty array falls back
# to CAP_GRANULARITY — same shape as PartyScaler.compute_floor's empty-array
# fallback, defensive against a pre-handshake / null-session caller.
static func compute_cap(party_levels: Array) -> int:
	if party_levels.is_empty():
		return CAP_GRANULARITY
	var min_level: int = int(party_levels[0])
	for raw in party_levels:
		var lvl := int(raw)
		if lvl < min_level:
			min_level = lvl
	if min_level <= 0:
		return CAP_GRANULARITY
	return int(ceil(float(min_level) / float(CAP_GRANULARITY))) * CAP_GRANULARITY

# Returns a NEW CharacterData representing the cap-level "synced-down" view
# of `char_data`. Base stats are recomputed at cap_level via CharacterData's
# per-class baselines; allocations are scaled by cap_level / actual_level
# (floor per stat) and re-applied via StatAllocator's increment table. The
# allocated_points dict on the returned character reflects the SCALED counts
# so a downstream re-application (item recompute, save round-trip) stays
# consistent with the visible stat fields.
#
# Items are NOT applied here — the caller's ItemStatApplicator pass should
# run on the returned character to layer equipped-item bonuses on top. This
# is what makes "items unchanged after sync-down" hold: the cap only owns
# the base + allocation slice of the stat pipeline.
#
# No-op contract: if char_data.level <= cap_level, returns a plain clone so
# solo players (whose cap is always >= their level under compute_cap's
# ceil-to-decade formula) and at-cap players see no transformation.
static func apply_cap_to_character(char_data: CharacterData, cap_level: int) -> CharacterData:
	if char_data == null:
		return null
	if char_data.level <= cap_level:
		return char_data.clone()
	var klass: int = char_data.character_class
	var actual_level: int = char_data.level
	var c := char_data.clone()
	c.level = cap_level
	# Reset class-baseline stats to cap_level baselines. Only max_hp / max_mp
	# are actually level-dependent today (CharacterData.base_*_for ignores lvl
	# for the others), but resetting all of them keeps the contract honest if
	# a future per-class curve is added.
	c.max_hp = CharacterData.base_max_hp_for(klass, cap_level)
	c.attack = CharacterData.base_attack_for(klass, cap_level)
	c.defense = CharacterData.base_defense_for(klass, cap_level)
	c.speed = CharacterData.base_speed_for(klass, cap_level)
	c.magic_attack = CharacterData.base_magic_attack_for(klass, cap_level)
	c.max_mp = CharacterData.base_max_mp_for(klass, cap_level)
	c.magic_resistance = CharacterData.base_magic_resistance_for(klass, cap_level)
	c.mp_regen = CharacterData.base_mp_regen_for(klass, cap_level)
	c.regeneration = CharacterData.base_regeneration_for(klass, cap_level)
	# Stats with no per-class baseline (dexterity, evasion, crit, luck) are
	# pure allocations today — reset to the neutral floor so the scaled
	# allocation pass below is the sole source of value.
	c.dexterity = 0
	c.evasion = 0.0
	c.crit_chance = 0.0
	c.luck = 0
	var ratio: float = float(cap_level) / float(actual_level)
	var scaled_alloc: Dictionary = {}
	for stat in char_data.allocated_points.keys():
		var pts: int = int(char_data.allocated_points[stat])
		var scaled: int = int(floor(float(pts) * ratio))
		scaled_alloc[stat] = scaled
		if scaled == 0:
			continue
		if StatAllocator.INT_INCREMENTS.has(stat):
			var delta: int = int(StatAllocator.INT_INCREMENTS[stat]) * scaled
			var cur: Variant = c.get(stat)
			if cur != null:
				c.set(stat, int(cur) + delta)
		elif StatAllocator.FLOAT_INCREMENTS.has(stat):
			var fdelta: float = float(StatAllocator.FLOAT_INCREMENTS[stat]) * float(scaled)
			var cur_f: Variant = c.get(stat)
			if cur_f != null:
				c.set(stat, float(cur_f) + fdelta)
	c.allocated_points = scaled_alloc
	c.hp = c.max_hp
	c.magic_points = c.max_mp
	return c

# Mutates a PartyMember's effective_stats to the capped view. Real stats
# stay intact, so XP / level-up flow continues to land on the character's
# true level. Mirrors PartyScaler.apply_scaling's shape so the
# co-op handshake can pick whichever (floor scaling or decade cap) the
# session policy needs.
static func apply_cap_to_member(pm, cap_level: int) -> void:
	if pm == null:
		return
	pm.effective_stats = apply_cap_to_character(pm.real_stats, cap_level)

# Inverse of apply_cap_to_member: drops the capped view and restores
# effective_stats to a clone of real_stats. Called on party leave so the
# departing player walks away with their full stat sheet.
static func release_cap(pm) -> void:
	if pm == null or pm.real_stats == null:
		return
	pm.effective_stats = pm.real_stats.clone()
