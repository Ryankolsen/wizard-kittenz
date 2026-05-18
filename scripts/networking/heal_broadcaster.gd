class_name HealBroadcaster
extends RefCounted

# Co-op heal / buff fan-out: a Sleepy Kitten's SMART_HEAL / AOE_HEAL /
# GROUP_REGEN / PARTY_BUFF cast on one client needs to land HP and buff
# state on every other client's matching Player too. The local
# SpellEffectResolver already mutates target CharacterData directly
# (heal() / add_buff()); this broadcaster is the seam the wire layer
# reads to fan the same effect out to remote clients. The remote-side
# applier (RemoteHealApplier, issue #146) is a separate slice — this
# module just emits the contract.
#
# Why a relay (vs. per-id fan-out like XPBroadcaster): a heal/buff
# event is single-source. One cast produces one or more
# (caster_id, target_id, effect_kind, amount, duration) tuples. The
# wire bridge serializes each tuple to a packet; receiving clients
# look the target_id up in the "players" SceneTree group and apply
# once. No per-party-member multiplication is needed here — AOE
# fan-out happens at the resolver layer (one emit per target).
#
# Identity model: caster_id is the casting player's Nakama id (same
# id XPBroadcaster registers, same field Player.player_id carries).
# target_id is the receiving player's Nakama id; empty target_id is
# the AOE / party-wide sentinel reserved for future broadcasts that
# can't enumerate party members at cast time (current resolver paths
# always emit per-target, so callers see one emission per ally).
# effect_kind is the Spell.EffectKind name ("SMART_HEAL", "AOE_HEAL",
# "GROUP_REGEN", "PARTY_BUFF") so the receiver can route to heal()
# vs. add_buff(). amount is HP (heals) or stat delta (PARTY_BUFF
# tracks defense + magic_resistance via two emissions). duration is
# the buff window in seconds — 0.0 for instant heals (SMART_HEAL,
# AOE_HEAL), >0 for buffs (GROUP_REGEN, PARTY_BUFF).
signal heal_applied(caster_id: String, target_id: String, effect_kind: String, amount: int, duration: float)

# Fans a heal / buff event out to subscribers. Returns true on emission,
# false on a guarded no-op (empty caster_id — the receiving client
# can't resolve the casting Player without it). target_id is allowed
# to be empty (AOE/party-wide sentinel); amount and duration are not
# guarded here because legitimate cases vary (heal amount 0 on a
# full-HP SMART_HEAL still emits so observers see the cast; duration
# 0 on instant heals).
func on_heal_applied(caster_id: String, target_id: String, effect_kind: String, amount: int, duration: float) -> bool:
	if caster_id == "":
		return false
	heal_applied.emit(caster_id, target_id, effect_kind, amount, duration)
	return true
