class_name RemoteTauntApplier
extends RefCounted

# Inbound-from-wire counterpart to TauntBroadcaster (PRD #124, co-op
# follow-up to #128). The wire layer (still dark) receives a
# (caster_id, enemy_id, duration) packet from a remote client; this
# helper walks the local "enemies" group and stamps taunt_source_id +
# taunt_remaining on the matching EnemyData so the receiving client's
# Enemy node has the cross-client identity needed to redirect its AI.
#
# Sibling-shaped to RemoteEnemyDespawner: a SceneTree group walk (no
# parallel id->node registry — EnemyStateSyncManager only tracks ids
# today, not node references). Single $Enemy per room currently;
# iteration cost stays trivial as spawn density grows. Same trade-off
# RemoteEnemyDespawner already accepted for the kill-side fan-in.
#
# What this DOES write:
#   - data.taunt_source_id = caster_id  (the cross-client identity the
#     future Enemy._select_taunt_target lookup-by-id branch will read)
#   - data.taunt_remaining = duration   (the same window the local-cast
#     resolver branch writes; tick_taunt decays + clears both fields
#     together on expiry)
#
# What this does NOT write:
#   - data.taunt_target — that's a CharacterData reference the receiving
#     client doesn't have (no caster CharacterData object on this
#     side). The Enemy AI's cross-client lookup-by-id path (separate
#     slice) is what consumes taunt_source_id to find the local Player
#     node by Nakama id. Until that lands, the receiving client's AI
#     keeps targeting nearest-player; the data is stamped, ready.
#
# Returns true on a stamped enemy (rising edge), false on:
#   - null tree (test path / pre-scene-add)
#   - empty caster_id (corrupted packet — without an identity, the
#     downstream lookup-by-id has nothing to match against)
#   - empty enemy_id (same shape as RemoteEnemyDespawner's guard;
#     iterating with empty id would match every Enemy whose data
#     .enemy_id defaults to "")
#   - non-positive duration (cleared taunt, not a new one — mirrors
#     TauntBroadcaster.on_taunt_applied's own guard)
#   - no matching Enemy in the "enemies" group (already despawned, or
#     this client never spawned that enemy locally)

static func apply(
	tree: SceneTree,
	caster_id: String,
	enemy_id: String,
	duration: float,
) -> bool:
	if tree == null:
		return false
	if caster_id == "":
		return false
	if enemy_id == "":
		return false
	if duration <= 0.0:
		return false
	var stamped := false
	for node in tree.get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var e := node as Enemy
		if e.data == null:
			continue
		if e.data.enemy_id != enemy_id:
			continue
		e.data.taunt_source_id = caster_id
		e.data.taunt_remaining = duration
		stamped = true
	return stamped
