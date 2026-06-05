class_name RemoteEnemyDamageApplier
extends RefCounted

# Data-side counterpart to RemoteDamageVisualizer (PRD #341, issue #342).
# When OP_DAMAGE_DEALT arrives for an enemy on a non-attacker peer, the
# floating number already paints via RemoteDamageVisualizer — but the
# enemy's local HP was never decremented (the hit landed on the
# attacker's HP copy), so the polled enemy_health_bar / boss_health_bar
# never moves on remote screens. This helper subtracts the broadcast
# damage from the matching local Enemy.data.hp so the bar drops in
# lockstep with the number.
#
# Despawn is still owned by OP_KILL → RemoteEnemyDespawner. A dropped
# OP_DAMAGE_DEALT is at worst a brief cosmetic bar discrepancy; the
# kill packet remains the authoritative removal signal even if the
# delta path drives HP to the floor on its own.
#
# Iterates the "enemies" group (same convention as RemoteDamageVisualizer
# and RemoteEnemyDespawner) rather than maintaining a parallel id→node
# registry — scene tree is the source of truth for "what's on screen".
#
# Returns true when a matching enemy's HP was decremented, false on:
#   - null tree (test / pre-scene-add path)
#   - empty enemy_id (defensive — pre-spawn-layer / corrupted packet)
#   - non-positive damage (mirrors the send-side and visualizer guards)
#   - no matching Enemy in the "enemies" group (silent no-op — already
#     despawned on this receiver, or never spawned locally)

static func apply(tree: SceneTree, enemy_id: String, damage: int) -> bool:
	if tree == null:
		return false
	if enemy_id == "":
		return false
	if damage <= 0:
		return false
	for node in tree.get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var e := node as Enemy
		if e.data == null:
			continue
		if e.data.enemy_id != enemy_id:
			continue
		e.data.hp = max(0, e.data.hp - damage)
		return true
	return false
