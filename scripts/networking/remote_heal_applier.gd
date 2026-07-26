class_name RemoteHealApplier
extends RefCounted

# Inbound-from-wire counterpart to HealBroadcaster (PRD #140, issue #146).
# The wire layer receives a (caster_id, target_id, effect_kind, amount,
# duration) packet from a remote client; this helper walks the local
# "players" SceneTree group and applies the matching effect to the
# matching Player's CharacterData.
#
# Sibling-shaped to RemoteTauntApplier — SceneTree group walk, all-static,
# idempotent guards. Distinct from it because heals/buffs mutate live HP
# and active-buff state (not just stamping identity fields).
#
# effect_kind dispatch:
#   - "SMART_HEAL" / "AOE_HEAL": data.heal(amount) — instant HP restore,
#     clamped to max_hp by heal()'s own contract.
#   - "GROUP_REGEN": data.add_buff(BUFF_GROUP_REGEN, amount, duration) —
#     HP-over-time tick driven by tick_buffs.
#   - "PARTY_BUFF_<STAT>": data.add_buff(<stat>, amount, duration) — the
#     stat name is embedded in the effect_kind string itself (e.g.
#     "PARTY_BUFF_DEFENSE", "PARTY_BUFF_MAGIC_RESISTANCE"), so any
#     generalized PARTY_BUFF stat (#425) works without adding a new case
#     here as long as the stat field exists on CharacterData.
#   - "PARTY_BUFF_DAMAGE_MULT": data.add_damage_mult_buff(amount / 100.0,
#     duration) — amount is wire-encoded as an integer percent by
#     SpellEffectResolver (1.2x -> 120) since the heal_applied signal's
#     amount field is int.
#
# These PARTY_BUFF_* variants mirror SpellEffectResolver's per-stat
# emissions (e.g. defense + magic_resistance for Cozy Aura / Guardian's
# Grace) so the wire stays 1:1 with the local add_buff calls without
# forcing the receiver to know how many stats a given spell bundles.
#
# AOE / party-wide sentinel: target_id == "" means "every player in the
# 'players' group". The local-cast paths in SpellEffectResolver always
# emit per-target so this branch is reserved for future broadcasts that
# can't enumerate party members at cast time, but the applier handles it
# today for forward-compatibility.
#
# Returns true on at least one applied effect (rising edge), false on:
#   - null tree (test path / pre-scene-add)
#   - empty caster_id (corrupted packet)
#   - unknown effect_kind (forward-compat guard against a future variant
#     a stale client doesn't recognize)
#   - no matching player in the "players" group (already despawned, or
#     this client never spawned that player locally)

static func apply(
	tree: SceneTree,
	target_id: String,
	effect_kind: String,
	amount: int,
	duration: float,
) -> bool:
	if tree == null:
		return false
	if effect_kind == "":
		return false
	var applied := false
	for node in tree.get_nodes_in_group("players"):
		if not ("data" in node) or not ("player_id" in node):
			continue
		if node.data == null:
			continue
		if target_id != "" and node.player_id != target_id:
			continue
		var hp_before: int = node.data.hp
		if _apply_to(node.data, effect_kind, amount, duration):
			applied = true
			if effect_kind in ["SMART_HEAL", "AOE_HEAL"]:
				var healed: int = node.data.hp - hp_before
				if healed > 0:
					FloatingText.spawn(node, str(healed), Color(0.2, 1.0, 0.4))
	return applied

const _PARTY_BUFF_PREFIX := "PARTY_BUFF_"

static func _apply_to(data: CharacterData, effect_kind: String, amount: int, duration: float) -> bool:
	match effect_kind:
		"SMART_HEAL", "AOE_HEAL":
			if amount <= 0:
				return false
			data.heal(amount)
			return true
		"GROUP_REGEN":
			if amount <= 0 or duration <= 0.0:
				return false
			data.add_buff(CharacterData.BUFF_GROUP_REGEN, amount, duration)
			return true
		"PARTY_BUFF_DAMAGE_MULT":
			if amount <= 0 or duration <= 0.0:
				return false
			data.add_damage_mult_buff(float(amount) / 100.0, duration)
			return true
	if effect_kind.begins_with(_PARTY_BUFF_PREFIX):
		if amount <= 0 or duration <= 0.0:
			return false
		var stat := effect_kind.substr(_PARTY_BUFF_PREFIX.length()).to_lower()
		if not (stat in data):
			return false
		data.add_buff(stat, amount, duration)
		return true
	return false
