class_name SpellEffectResolver
extends RefCounted

# Preload HealBroadcaster — sibling class_name lookup is load-order-fragile
# in Godot 4.x when the class was added in the same change as the caller
# (same workaround CoopSession uses for TauntSyncOutboundBridgeRef).
const HealBroadcasterRef = preload("res://scripts/networking/heal_broadcaster.gd")

# Dispatches a Spell's effect over a target list based on EffectKind. Spells
# bypass DamageResolver — `power` is the raw magic damage dealt, then the
# Wire Combat Stats (PRD #85) pipeline applies:
#   effective_power = spell.power + caster.magic_attack
#   CritResolver.roll_crit(caster.crit_chance) ⇒ 2× on success
#   per-target: max(1, effective_power - target.magic_resistance)
# magic_resistance / magic_attack / crit_chance are duck-typed reads with a
# default of 0 so EnemyData (no such fields) does not crash.
# Evasion is intentionally NOT rolled here — spells always land; only
# magic_resistance mitigates.
# Returns total HP removed across all targets so callers can drive popups /
# kill-reward XP awards from a single number.

# Issue #423: BUFF-kind skills are self-targeted and distinct enough in
# shape (damage multiplier vs. flat stat buff vs. buff+shield combo) that
# they're dispatched by spell.id rather than a single generic formula, the
# same way PARTY_BUFF/GROUP_REGEN are currently one hardcoded skill each.
const CATNIP_CURSE_MULT := 1.25
const CATNIP_CURSE_DURATION := 10.0
const MAXIMUM_CHONK_STAT_AMOUNT := 5
const MAXIMUM_CHONK_DURATION := 12.0
const IRON_HIDE_DEFENSE_AMOUNT := 10
const IRON_HIDE_SHIELD_AMOUNT := 15
const IRON_HIDE_DURATION := 20.0

# Issue #457: Phase Tome I, the first Tome-reward spell (PRD #453). A normal
# cast/cooldown self-buff, same dispatch shape as Catnip Curse/Iron Hide
# above — sets the caster's invulnerable flag (CharacterData.set_invulnerable)
# for a fixed duration rather than a stat/shield combo.
const PHASE_TOME_I_INVULNERABLE_DURATION := 2.0

# Issue #424: PARTY_SHIELD is dispatched generically (unlike BUFF above) since
# Cozy Cocoon is its only consumer so far — same shape as GROUP_REGEN/
# PARTY_BUFF's "one hardcoded skill" precedent, just shield instead of buff.
# Nine Lives extends SMART_HEAL by id: a full heal plus a shield on the same
# lowest-HP pick, so it stays inside the SMART_HEAL branch rather than
# introducing a new EffectKind.
const COZY_COCOON_SHIELD_AMOUNT := 10
const COZY_COCOON_DURATION := 12.0
const NINE_LIVES_SHIELD_AMOUNT := 20
const NINE_LIVES_DURATION := 8.0

# Issue #426: DOT is dispatched by spell.id, same convention as BUFF above,
# since Bloodclaw Rend (single target) and Arcane Wildfire (AoE burn) need
# different target-scoping despite sharing one EffectKind. Tick amount uses
# effective_power (spell.power + magic_attack, crit-eligible) so DOT scales
# with caster stats the same way DAMAGE/AREA do; duration is a fixed
# per-skill constant, matching how PARTY_SHIELD/GROUP_REGEN hardcode
# duration rather than storing it on Spell.
const BLOODCLAW_REND_DOT_DURATION := 5.0
const ARCANE_WILDFIRE_DOT_DURATION := 6.0

# Issue #427: DEBUFF is dispatched by spell.id, same convention as BUFF/DOT
# above. Mind Sunder is a fixed -defense amount (not effective_power-scaled)
# since it's a stat debuff on the target rather than damage — matches how
# IRON_HIDE_DEFENSE_AMOUNT/COZY_COCOON_SHIELD_AMOUNT are fixed constants
# rather than caster-stat-scaled formulas.
const MIND_SUNDER_DEFENSE_AMOUNT := 4
const MIND_SUNDER_DURATION := 10.0

# Issue #428: Unstoppable Chonk composes TAUNT (existing per-target dispatch)
# with a self-shield and a self-defense-buff in one cast/cooldown, rather than
# being three separate spells. Taunt duration (8s) is intentionally its own
# constant distinct from the spell's 12s cooldown — unlike the plain TAUNT
# case above (which reuses spell.cooldown as duration since Chonk Taunt's
# only consumer has no separate cooldown/duration split). Shield and defense
# share a 10s duration, matching Iron Hide's (#423) precedent of a buff+shield
# combo using one duration for both parts.
const UNSTOPPABLE_CHONK_TAUNT_DURATION := 8.0
const UNSTOPPABLE_CHONK_SHIELD_AMOUNT := 25
const UNSTOPPABLE_CHONK_DEFENSE_AMOUNT := 10
const UNSTOPPABLE_CHONK_DURATION := 10.0

static func apply(spell: Spell, caster, targets: Array, rng: RandomNumberGenerator = null, taunt_broadcaster: TauntBroadcaster = null, caster_id: String = "", heal_broadcaster: HealBroadcasterRef = null) -> int:
	if spell == null:
		return 0
	var effective_power := spell.power + _read_int(caster, "magic_attack", 0)
	var crit_chance := _read_float(caster, "crit_chance", 0.0)
	if CritResolver.roll_crit(crit_chance, rng):
		effective_power *= 2
	var total := 0
	match spell.effect_kind:
		Spell.EffectKind.DAMAGE:
			for t in targets:
				var t_data = _data_of(t)
				if t_data != null and t_data.is_alive():
					total += _apply_magic_damage_to_target(t, effective_power)
					break
		Spell.EffectKind.AREA:
			for t in targets:
				var t_data = _data_of(t)
				if t_data != null and t_data.is_alive():
					total += _apply_magic_damage_to_target(t, effective_power)
		Spell.EffectKind.BUFF:
			# Self-targeted buff. Dispatched per skill id -- see constants above.
			# Unknown ids are a no-op so a placeholder BUFF spell (tests, future
			# content) doesn't crash.
			match spell.id:
				"catnip_curse":
					if caster != null and caster.has_method("add_damage_mult_buff"):
						caster.add_damage_mult_buff(CATNIP_CURSE_MULT, CATNIP_CURSE_DURATION)
				"maximum_chonk":
					if caster != null and caster.has_method("add_buff"):
						caster.add_buff("attack", MAXIMUM_CHONK_STAT_AMOUNT, MAXIMUM_CHONK_DURATION)
						caster.add_buff("defense", MAXIMUM_CHONK_STAT_AMOUNT, MAXIMUM_CHONK_DURATION)
						caster.add_buff("magic_resistance", MAXIMUM_CHONK_STAT_AMOUNT, MAXIMUM_CHONK_DURATION)
				"iron_hide":
					if caster != null:
						if caster.has_method("add_buff"):
							caster.add_buff("defense", IRON_HIDE_DEFENSE_AMOUNT, IRON_HIDE_DURATION)
						if caster.has_method("add_shield"):
							caster.add_shield(IRON_HIDE_SHIELD_AMOUNT, IRON_HIDE_DURATION)
				"phase_tome_i":
					if caster != null and caster.has_method("set_invulnerable"):
						caster.set_invulnerable(PHASE_TOME_I_INVULNERABLE_DURATION)
		Spell.EffectKind.HEAL:
			# Self-heal: amount = spell.power + caster.magic_attack, clamped
			# at max_hp by CharacterData.heal(). Crit is intentionally NOT
			# rolled — keeps heal output deterministic for stat tuning. The
			# `targets` list is ignored; party-wide heal is a future variant.
			if caster != null and caster.has_method("heal"):
				var heal_amount := spell.power + _read_int(caster, "magic_attack", 0)
				total += int(caster.heal(heal_amount))
		Spell.EffectKind.SMART_HEAL:
			# Issue #141: picks the ally with the lowest HP percentage from the
			# targets array (ties broken by array order). Falls back to caster
			# when targets is empty or every target is already at full HP. Heal
			# amount uses spell.power + magic_attack, same formula as HEAL;
			# crit is intentionally NOT rolled (matches HEAL's deterministic
			# tuning).
			var pick = _lowest_hp_pct_target(targets)
			if pick == null:
				pick = caster
			if spell.id == "nine_lives":
				# Capstone (#424): full heal (to max_hp) plus a shield on
				# the same lowest-HP pick, in one cast.
				if pick != null and pick.has_method("heal") and "max_hp" in pick:
					var full_amount := int(pick.get("max_hp"))
					var full_dealt := int(pick.heal(full_amount))
					total += full_dealt
					if pick.has_method("add_shield"):
						pick.add_shield(NINE_LIVES_SHIELD_AMOUNT, NINE_LIVES_DURATION)
					if heal_broadcaster != null:
						heal_broadcaster.on_heal_applied(caster_id, _read_player_id(pick), "NINE_LIVES", full_dealt, 0.0)
			else:
				var smart_amount := spell.power + _read_int(caster, "magic_attack", 0)
				if pick != null and pick.has_method("heal"):
					var smart_dealt := int(pick.heal(smart_amount))
					total += smart_dealt
					if heal_broadcaster != null:
						heal_broadcaster.on_heal_applied(caster_id, _read_player_id(pick), "SMART_HEAL", smart_dealt, 0.0)
		Spell.EffectKind.AOE_HEAL:
			# Issue #141: heals every entry in the targets array. Caster is
			# included only if the caller put it in the array. Returns the sum
			# of HP restored across all targets.
			var aoe_amount := spell.power + _read_int(caster, "magic_attack", 0)
			for t in targets:
				if t != null and t.has_method("heal"):
					var aoe_dealt := int(t.heal(aoe_amount))
					total += aoe_dealt
					if heal_broadcaster != null:
						heal_broadcaster.on_heal_applied(caster_id, _read_player_id(t), "AOE_HEAL", aoe_dealt, 0.0)
		Spell.EffectKind.GROUP_REGEN:
			# Regen Snooze: 2 HP/sec for 15s per target. Driven by
			# CharacterData.tick_buffs — passive regen is suppressed in
			# Player._tick_regeneration for the buff's duration so the two
			# don't stack (issue #144).
			for t in targets:
				if t != null and t.has_method("add_buff"):
					t.add_buff(CharacterData.BUFF_GROUP_REGEN, 2, 15.0)
					if heal_broadcaster != null:
						heal_broadcaster.on_heal_applied(caster_id, _read_player_id(t), "GROUP_REGEN", 2, 15.0)
		Spell.EffectKind.PARTY_BUFF:
			# Issue #425: generalized — the stat(s)/amount/duration, or a
			# damage-multiplier magnitude, come from the spell's own data
			# (set at construction in skill_tree.gd) rather than being
			# hardcoded to Cozy Aura. add_buff mutates the stat field
			# directly so the rest of the damage pipeline reads the boosted
			# values transparently; tick_buffs reverts on expiry (#144).
			for t in targets:
				if t == null:
					continue
				if spell.party_buff_damage_mult > 0.0:
					if t.has_method("add_damage_mult_buff"):
						t.add_damage_mult_buff(spell.party_buff_damage_mult, spell.party_buff_duration)
						if heal_broadcaster != null:
							# Magnitude is wire-encoded as an integer percent
							# (1.2 -> 120) since the heal_applied signal's
							# amount field is int; RemoteHealApplier decodes
							# it back to a float on the receiving side.
							heal_broadcaster.on_heal_applied(caster_id, _read_player_id(t), "PARTY_BUFF_DAMAGE_MULT",
								roundi(spell.party_buff_damage_mult * 100.0), spell.party_buff_duration)
				elif t.has_method("add_buff"):
					for entry in spell.party_buff_stats:
						t.add_buff(entry.stat, entry.amount, spell.party_buff_duration)
						if heal_broadcaster != null:
							# One emission per stat keeps the wire packet 1:1
							# with the local add_buff calls — the receiver
							# can apply each stat delta independently without
							# knowing how many stats a given spell bundles.
							heal_broadcaster.on_heal_applied(caster_id, _read_player_id(t), "PARTY_BUFF_" + String(entry.stat).to_upper(),
								entry.amount, spell.party_buff_duration)
		Spell.EffectKind.PARTY_SHIELD:
			# Cozy Cocoon: shields every entry in the targets array. Follows
			# the same "loop targets, duck-type the method" convention as
			# GROUP_REGEN/PARTY_BUFF above (issue #424).
			for t in targets:
				if t != null and t.has_method("add_shield"):
					t.add_shield(COZY_COCOON_SHIELD_AMOUNT, COZY_COCOON_DURATION)
					if heal_broadcaster != null:
						heal_broadcaster.on_heal_applied(caster_id, _read_player_id(t), "PARTY_SHIELD", COZY_COCOON_SHIELD_AMOUNT, COZY_COCOON_DURATION)
		Spell.EffectKind.DOT:
			# Unknown ids are a no-op, same safety net as BUFF's dispatch.
			match spell.id:
				"bloodclaw_rend":
					# Single-target: first living, DOT-capable target only.
					for t in targets:
						var t_data = _data_of(t)
						if t_data != null and t_data.is_alive() and t_data.has_method("apply_dot"):
							t_data.apply_dot(effective_power, BLOODCLAW_REND_DOT_DURATION)
							break
				"arcane_wildfire":
					# AREA + DOT: applies to every living target in range.
					for t in targets:
						var t_data = _data_of(t)
						if t_data != null and t_data.is_alive() and t_data.has_method("apply_dot"):
							t_data.apply_dot(effective_power, ARCANE_WILDFIRE_DOT_DURATION)
		Spell.EffectKind.DEBUFF:
			# Unknown ids are a no-op, same safety net as BUFF/DOT's dispatch.
			match spell.id:
				"mind_sunder":
					# Single-target: first living, debuff-capable target only,
					# same target-scoping as Bloodclaw Rend's single-target DOT.
					for t in targets:
						var t_data = _data_of(t)
						if t_data != null and t_data.is_alive() and t_data.has_method("apply_debuff"):
							t_data.apply_debuff("defense", MIND_SUNDER_DEFENSE_AMOUNT, MIND_SUNDER_DURATION)
							break
		Spell.EffectKind.TAUNT:
			# Redirects each target enemy's AI to fixate on the caster for
			# spell.cooldown seconds (or UNSTOPPABLE_CHONK_TAUNT_DURATION, which
			# is shorter than that capstone's 12s cooldown). Targets without the
			# taunt fields (e.g. CharacterData) are skipped duck-type style.
			var taunt_duration := spell.cooldown
			if spell.id == "unstoppable_chonk":
				taunt_duration = UNSTOPPABLE_CHONK_TAUNT_DURATION
				if caster != null:
					if caster.has_method("add_shield"):
						caster.add_shield(UNSTOPPABLE_CHONK_SHIELD_AMOUNT, UNSTOPPABLE_CHONK_DURATION)
					if caster.has_method("add_buff"):
						caster.add_buff("defense", UNSTOPPABLE_CHONK_DEFENSE_AMOUNT, UNSTOPPABLE_CHONK_DURATION)
			for t in targets:
				if t == null:
					continue
				if "taunt_target" in t and "taunt_remaining" in t:
					t.taunt_target = caster
					t.taunt_remaining = taunt_duration
					# Cross-client identity: stamp taunt_source_id so the
					# receiving client (which has no caster CharacterData
					# reference) can resolve the taunting player by id.
					# Duck-typed in case a legacy taunt-capable target ever
					# lacks the field; empty caster_id is left as-is so a
					# solo cast doesn't pollute the field with "".
					if "taunt_source_id" in t and caster_id != "":
						t.taunt_source_id = caster_id
					# Co-op fan-out: per-enemy emit. Broadcaster's own
					# guards (empty caster_id / empty enemy_id / non-
					# positive duration) drop malformed entries — e.g.
					# legacy test enemies without enemy_id no-op cleanly.
					if taunt_broadcaster != null:
						var eid := ""
						if "enemy_id" in t:
							eid = str(t.enemy_id)
						taunt_broadcaster.on_taunt_applied(caster_id, eid, spell.cooldown)
	return total

# Returns the target with the strictly lowest HP percentage (hp / max_hp).
# Targets that are full HP, dead, or lack hp/max_hp fields are skipped. Ties
# are broken by array order (first occurrence wins). Returns null when no
# eligible target exists so the caller can fall back to the caster.
static func _lowest_hp_pct_target(targets: Array):
	var best = null
	var best_pct := 2.0
	for t in targets:
		if t == null:
			continue
		if not ("hp" in t and "max_hp" in t):
			continue
		var hp_val := int(t.get("hp"))
		var max_val := int(t.get("max_hp"))
		if max_val <= 0 or hp_val >= max_val:
			continue
		var pct := float(hp_val) / float(max_val)
		if pct < best_pct:
			best_pct = pct
			best = t
	return best

static func _read_player_id(target) -> String:
	if target == null or typeof(target) != TYPE_OBJECT:
		return ""
	if "player_id" in target:
		return str(target.get("player_id"))
	return ""

static func _mitigated(effective_power: int, target) -> int:
	var resistance := _read_int(target, "magic_resistance", 0)
	return maxi(1, effective_power - resistance)

# Issue #343 (PRD #341 — Typed damage points): apply the magic-damage pulse
# and spawn the magic-colored floating number when the target is a scene
# node. Accepts both legacy data-only targets (CharacterData/EnemyData/test
# fakes — no scene presence, no label) and Enemy scene nodes (data lives on
# `.data`, label is parented to the enemy's scene parent so it survives a
# same-frame queue_free, mirroring FloatingText.spawn_at). Color comes from
# the single DamageKind.color_for mapping shared with the local melee and
# remote visualizer paths so solo and co-op render identically.
static func _apply_magic_damage_to_target(t, effective_power: int) -> int:
	var t_data = _data_of(t)
	if t_data == null:
		return 0
	var dealt: int = int(t_data.take_damage(_mitigated(effective_power, t_data)))
	if dealt > 0 and t is Node2D:
		FloatingText.spawn_at(t, str(dealt), DamageKind.color_for(DamageKind.Kind.MAGIC))
	return dealt

# Resolves the data-bearing object behind a target reference. An Enemy
# scene node wraps EnemyData on `.data`; legacy data-only targets are
# returned as-is. Keeps duck-typed extension simple: anything else with a
# `data` field falls through to data-only handling.
static func _data_of(t):
	if t == null:
		return null
	if t is Enemy:
		return (t as Enemy).data
	return t

static func _read_int(obj, key: String, default_val: int) -> int:
	if obj == null or typeof(obj) != TYPE_OBJECT:
		return default_val
	if key in obj:
		return int(obj.get(key))
	return default_val

static func _read_float(obj, key: String, default_val: float) -> float:
	if obj == null or typeof(obj) != TYPE_OBJECT:
		return default_val
	if key in obj:
		return float(obj.get(key))
	return default_val
