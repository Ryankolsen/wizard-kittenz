class_name RemoteEnemyDespawner
extends RefCounted

# Scene-tree counterpart to RemoteKillApplier. Closes AC#4 ("Enemy death
# is consistent across all clients (no ghost enemies)") on the visual side
# of a remote-kill packet.
#
# When OP_KILL arrives for an enemy on a remote client, RemoteKillApplier
# marks it dead in session.enemy_sync — but the visible Enemy
# CharacterBody2D in that client's scene tree never had its HP touched
# (the killing blow happened on the sender's HP copy), so its AI state
# machine never transitions to DEAD and queue_free never fires. The enemy
# lingers as a "ghost" until the next room reload. This helper finds the
# matching Enemy node by enemy_id and queue_frees it so the visible enemy
# disappears at the same edge as the registry update.
#
# Split from RemoteKillApplier because:
#   - RemoteKillApplier is RefCounted pure data and exercised by tests
#     without a SceneTree. queue_free requires a tree, so bundling would
#     force the data-layer tests to spin up a tree.
#   - Matches the data-layer/scene-layer split the rest of the co-op
#     stack uses (CoopPlayerLayer renders, NetworkSyncManager interpolates;
#     EnemyStateSyncManager and RemoteKillApplier are pure-data peers).
#
# Iterates the "enemies" group (Enemy._ready adds itself on construction)
# rather than maintaining a parallel id->node registry. The scene tree
# is the source of truth for "what's on screen" — a side registry would
# risk staleness on scene reloads (every advance_to triggers a reload).
# Single $Enemy per room today; iteration cost stays trivial as spawn
# density grows.
#
# Returns true on a freed node (rising edge), false on:
#   - null tree (test / pre-scene-add path)
#   - empty enemy_id (defensive — pre-spawn-layer / corrupted packet;
#     same shape as RemoteKillApplier's own empty-id guard)
#   - no matching Enemy in the "enemies" group (already despawned by a
#     prior packet, or this client never spawned that enemy locally)
#
# Caller-side contract: GameState._on_kill_received gates the despawn
# behind RemoteKillApplier.apply's rising-edge true return, so a
# duplicate packet never re-queues an already-freed node. queue_free is
# itself idempotent in Godot (re-queueing a node-marked-for-deletion is
# a safe no-op), so a redundant call wouldn't crash — but skipping
# avoids the iteration entirely.

static func despawn(tree: SceneTree, enemy_id: String) -> bool:
	if tree == null:
		return false
	if enemy_id == "":
		return false
	var freed := false
	for node in tree.get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var e := node as Enemy
		if e.data == null:
			continue
		if e.data.enemy_id != enemy_id:
			continue
		e.queue_free()
		freed = true
	return freed
