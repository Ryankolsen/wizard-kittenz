class_name RemoteKillApplier
extends RefCounted

# Inbound-from-wire counterpart to KillRewardRouter. The wire layer
# (#14, HITL) receives an enemy-died packet (enemy_id, killer_id,
# xp_reward) from a remote client; this helper bundles the local-side
# data effects so the wire packet handler is a single one-liner per
# packet:
#
#   RemoteKillApplier.apply(GameState.coop_session, enemy_id, killer_id, xp)
#
# Two effects bundled:
#   1. session.enemy_sync.apply_death(enemy_id) — removes the enemy from
#      the local registry. apply_death's idempotency does the duplicate-
#      packet gating; a rising-edge erase (true) is the gate for firing
#      the rest of this method.
#   2. session.xp_broadcaster.on_enemy_killed(xp_value, killer_id) —
#      fans out the XP locally. Each client's LocalXPRouter (filtered
#      by its own player_id) picks its emission and applies the amount
#      to its member.real_stats. So a remote-killer kill still awards
#      XP to my local member — the AC#3 "a kill by any player awards
#      XP to all players" loop closes through this seam on the
#      receiving side.
#
# Sibling-shaped to KillRewardRouter:
#   - KillRewardRouter is the OUTBOUND seam (local kill -> broadcast +
#     registry mark; the wire layer reads from the broadcaster's
#     emissions or hooks into the kill flow to ship a packet)
#   - RemoteKillApplier is the INBOUND seam (wire packet -> registry
#     mark + broadcast; the local LocalXPRouter applies the XP)
# Both use the same registry (session.enemy_sync) and the same
# broadcaster (session.xp_broadcaster), so a host's local-kill flow
# and a remote-receive flow converge on the same idempotent state.
#
# What this does NOT do:
#   - Touch the scene tree. queue_free of the visible Enemy node is the
#     RemoteEnemyDespawner.despawn(get_tree(), enemy_id) call gated
#     behind this method's rising-edge true return at the call site
#     (GameState._on_kill_received). Split because this helper is pure
#     RefCounted data and exercised by tests without a SceneTree;
#     bundling queue_free here would force every data-layer test to
#     spin up a tree.
#   - Apply offline-XP tracking. Co-op kills never feed the offline
#     counter (matches KillRewardRouter's co-op branch contract:
#     co-op requires the network so the XP is already "synced", and
#     folding it into pending_xp would double-count when the next
#     solo-mode merge fires).
#
# Returns true on a fresh apply (rising-edge: enemy was alive, now
# dead), false on:
#   - null session (test path / pre-handshake)
#   - inactive session (constructed but not started, or already end()ed)
#   - empty enemy_id (defensive — pre-spawn-layer / corrupted packet;
#     can't gate idempotency without a stable id, so skip the broadcast
#     to avoid double-XP on a re-broadcast)
#   - null session.enemy_sync (test path / post-end race) — without a
#     registry to gate against, we don't fire the broadcast either
#   - already-dead (apply_death returned false: duplicate packet from a
#     flaky network OR an unknown id we never registered)
#
# True return is the gate the caller uses to decide whether to also
# fire the scene-tree side (queue_free the local enemy node). False
# means either the kill already applied OR something rejected — in
# both cases the scene-tree node is either already gone or was never
# there.

static func apply(
	session: CoopSession,
	enemy_id: String,
	killer_id: String = "",
	xp_value: int = 0,
) -> bool:
	if session == null:
		return false
	if not session.is_active():
		return false
	if enemy_id == "":
		return false
	if session.enemy_sync == null:
		return false
	# apply_death's idempotent-erase contract is the rising-edge gate.
	# A duplicate packet (host's race with our local kill, or a flaky-
	# network re-send) returns false here and the broadcast doesn't fire,
	# so XP applies exactly once per enemy across the local-kill +
	# remote-receive paths.
	if not session.enemy_sync.apply_death(enemy_id):
		return false
	# xp_broadcaster's own non-positive-amount guard means xp_value <= 0
	# falls through as a silent no-op; we don't need to re-check here.
	# A null broadcaster (test path / mid-end race) means there's nothing
	# to fan out to, but the registry erase still counted as a rising
	# edge — caller still drives the scene-tree side.
	if session.xp_broadcaster != null:
		session.xp_broadcaster.on_enemy_killed(xp_value, killer_id)
	return true
