class_name TauntBroadcaster
extends RefCounted

# Co-op TAUNT fan-out: a Chonk Kitten's TAUNT cast on one client needs to
# redirect that enemy's AI on every other client too. The local resolver
# stamps taunt_target on the enemy directly (already wired in
# SpellEffectResolver); this broadcaster is the seam the wire layer reads
# to fan the same taunt out to remote clients. The remote-side applier
# is a separate slice (sibling to RemoteKillApplier) — this module just
# emits the contract.
#
# Why a relay (not a per-id fan-out like XPBroadcaster):
#   XPBroadcaster emits once per registered player because every party
#   member receives the same XP. TAUNT is a single-source event — one
#   cast, one (caster_id, enemy_id, duration) tuple. The wire bridge
#   serializes that tuple to a packet; receiving clients apply it once.
#   No per-party-member multiplication is needed.
#
# Identity model: caster_id is the casting player's Nakama id (the same
# id XPBroadcaster registers). enemy_id is EnemyData.enemy_id — the
# stable per-spawn key the dungeon spawner mints, the same key
# EnemyStateSyncManager.apply_death uses. duration is the taunt window
# in seconds (mirrors SpellEffectResolver's `t.taunt_remaining = spell
# .cooldown` line). All three are required: empty caster_id or empty
# enemy_id means the event can't be addressed cross-client; non-positive
# duration is a no-op (cleared taunt, not a new one).
signal taunt_applied(caster_id: String, enemy_id: String, duration: float)

# Fans a TAUNT event out to subscribers. Returns true on emission, false
# on a guarded no-op (any input invalid). Same shape as XPBroadcaster
# .on_enemy_killed's non-positive guard so a malformed cast can't
# pollute the wire.
func on_taunt_applied(caster_id: String, enemy_id: String, duration: float) -> bool:
	if caster_id == "":
		return false
	if enemy_id == "":
		return false
	if duration <= 0.0:
		return false
	taunt_applied.emit(caster_id, enemy_id, duration)
	return true
