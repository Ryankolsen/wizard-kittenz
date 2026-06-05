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
			# Cozy Aura: +3 defense and +3 magic_resistance for 15s per
			# target. add_buff mutates the stat field directly so the rest
			# of the damage pipeline reads the boosted values transparently;
			# tick_buffs reverts both on expiry (issue #144).
			for t in targets:
				if t != null and t.has_method("add_buff"):
					t.add_buff("defense", 3, 15.0)
					t.add_buff("magic_resistance", 3, 15.0)
					if heal_broadcaster != null:
						# Two emissions per target keeps the wire packet 1:1
						# with the local add_buff calls — the receiver can
						# apply each stat delta independently without having
						# to know that Cozy Aura bundles defense+MR.
						var pid := _read_player_id(t)
						heal_broadcaster.on_heal_applied(caster_id, pid, "PARTY_BUFF_DEFENSE", 3, 15.0)
						heal_broadcaster.on_heal_applied(caster_id, pid, "PARTY_BUFF_MAGIC_RESISTANCE", 3, 15.0)
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
