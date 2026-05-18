class_name SpellEffectResolver
extends RefCounted

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

static func apply(spell: Spell, caster, targets: Array, rng: RandomNumberGenerator = null, taunt_broadcaster: TauntBroadcaster = null, caster_id: String = "") -> int:
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
				if t != null and t.is_alive():
					total += t.take_damage(_mitigated(effective_power, t))
					break
		Spell.EffectKind.AREA:
			for t in targets:
				if t != null and t.is_alive():
					total += t.take_damage(_mitigated(effective_power, t))
		Spell.EffectKind.BUFF:
			# No-op for the tracer. Future: register an active buff on caster
			# (+power attack for `cooldown` seconds, refresh on re-cast). The
			# kind classification is enough to mark it as a distinct effect.
			pass
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
			var smart_amount := spell.power + _read_int(caster, "magic_attack", 0)
			var pick = _lowest_hp_pct_target(targets)
			if pick == null:
				pick = caster
			if pick != null and pick.has_method("heal"):
				total += int(pick.heal(smart_amount))
		Spell.EffectKind.AOE_HEAL:
			# Issue #141: heals every entry in the targets array. Caster is
			# included only if the caller put it in the array. Returns the sum
			# of HP restored across all targets.
			var aoe_amount := spell.power + _read_int(caster, "magic_attack", 0)
			for t in targets:
				if t != null and t.has_method("heal"):
					total += int(t.heal(aoe_amount))
		Spell.EffectKind.GROUP_REGEN:
			# Issue #141 stub: real regen-over-time application waits on the
			# active-buff system in slice #3 (issue #144). No-crash placeholder
			# so solo-path tests pass and downstream slices can wire in the
			# buff without further resolver churn.
			pass
		Spell.EffectKind.PARTY_BUFF:
			# Issue #141 stub: defense + magic_resistance buff application
			# also waits on the active-buff system (#144). No-crash placeholder;
			# no state is mutated yet.
			pass
		Spell.EffectKind.TAUNT:
			# Redirects each target enemy's AI to fixate on the caster for
			# spell.cooldown seconds. Targets without the taunt fields (e.g.
			# CharacterData) are skipped duck-type style.
			for t in targets:
				if t == null:
					continue
				if "taunt_target" in t and "taunt_remaining" in t:
					t.taunt_target = caster
					t.taunt_remaining = spell.cooldown
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

static func _mitigated(effective_power: int, target) -> int:
	var resistance := _read_int(target, "magic_resistance", 0)
	return maxi(1, effective_power - resistance)

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
