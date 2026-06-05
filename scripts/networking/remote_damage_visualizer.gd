class_name RemoteDamageVisualizer
extends RefCounted

# Scene-tree visual side of an OP_DAMAGE_DEALT packet (PRD #328 slice 6,
# issue #334). When a remote teammate hits an enemy, every other client
# gets a damage_received signal — this helper finds the matching Enemy
# node by enemy_id in the "enemies" group and spawns the same
# FloatingText overlay the solo damage path uses, so the floating
# number appears above the enemy on every peer's screen.
#
# Split out of GameState (and out of NakamaLobby) for the same reason
# RemoteEnemyDespawner is split: GameState is autoload-only and harder
# to test, while a pure SceneTree helper is a single static call that
# can be exercised by a GUT test that builds a tiny tree, fires the
# helper, and walks the children.
#
# Iterates the "enemies" group (Enemy._ready adds itself on construction)
# rather than maintaining a parallel id→node registry — same rationale
# as RemoteEnemyDespawner. Single $Enemy per room today; iteration cost
# stays trivial as spawn density grows.
#
# Returns true on a spawned FloatingText (rising edge), false on:
#   - null tree (test / pre-scene-add path)
#   - empty enemy_id (defensive — pre-spawn-layer / corrupted packet)
#   - non-positive damage (no number to render; matches send-side guard)
#   - no matching Enemy in the "enemies" group (already despawned on this
#     receiver — silent no-op per AC#6)

# Color comes from DamageKind.color_for so solo and co-op render
# identically (PRD #341 — Typed damage points). With #346 the wire now
# carries the kind alongside {enemy_id, damage}; pre-#346 senders omit
# the key and NakamaLobby._route_damage_dealt defaults the decoded kind
# to PHYSICAL, so an older sender's hits paint the same red overlay
# they did before this slice. Unknown / out-of-range kinds also fold
# to PHYSICAL inside DamageKind.color_for.

static func spawn(tree: SceneTree, enemy_id: String, damage: int, kind: int = DamageKind.Kind.PHYSICAL) -> bool:
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
		FloatingText.spawn_at(e, str(damage), DamageKind.color_for(kind))
		return true
	return false
