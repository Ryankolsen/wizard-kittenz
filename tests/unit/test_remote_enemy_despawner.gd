extends GutTest

# Tests for RemoteEnemyDespawner — the scene-tree counterpart to
# RemoteKillApplier that closes AC#4 ("no ghost enemies") on the visual
# side of a remote-kill packet.
#
# Use add_child_autofree(enemy) so a queued-for-deletion node is still
# freed at end-of-test even if despawn() didn't fire — keeps the SceneTree
# clean between assertions.

func _make_enemy_in_tree(enemy_id: String) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e.data.enemy_id = enemy_id
	add_child_autofree(e)
	return e

func test_despawn_returns_false_on_null_tree():
	# Test path / pre-scene-add: no tree to iterate.
	assert_false(RemoteEnemyDespawner.despawn(null, "r1_e0"))

func test_despawn_returns_false_on_empty_enemy_id():
	# Defensive — corrupted packet / pre-spawn-layer path. Iterating with
	# an empty id would match every Enemy whose data.enemy_id happens to
	# default to "", which would mass-free legitimate enemies.
	assert_false(RemoteEnemyDespawner.despawn(get_tree(), ""))

func test_despawn_returns_false_when_no_matching_enemy():
	# Already despawned by a prior packet OR never registered locally.
	# A non-match must not flag a rising-edge.
	_make_enemy_in_tree("r1_e0")
	assert_false(RemoteEnemyDespawner.despawn(get_tree(), "r1_e_does_not_exist"))

func test_despawn_returns_true_and_queues_enemy_for_deletion():
	# AC#4: the visible Enemy disappears at the same edge as the registry
	# update.
	var e := _make_enemy_in_tree("r1_e0")
	assert_false(e.is_queued_for_deletion(),
		"sanity: enemy not pre-queued")
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	assert_true(e.is_queued_for_deletion(),
		"matching enemy was queued for deletion")

func test_despawn_only_frees_matching_id():
	# Multiple enemies in the tree (cross-room or test fixture); despawn
	# must surgically free only the one matching enemy_id.
	var e1 := _make_enemy_in_tree("r1_e0")
	var e2 := _make_enemy_in_tree("r2_e0")
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	assert_true(e1.is_queued_for_deletion(),
		"target enemy was queued")
	assert_false(e2.is_queued_for_deletion(),
		"non-matching enemy was not queued")

func test_despawn_handles_enemy_with_null_data():
	# A pre-_setup_current_room Enemy node (data not yet assigned) is in
	# the "enemies" group but has no enemy_id. Defensive null-check must
	# skip it rather than crash on e.data.enemy_id.
	var bare := Enemy.new()
	bare.data = null
	add_child_autofree(bare)
	# The real target still gets freed.
	var target := _make_enemy_in_tree("r1_e0")
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	assert_true(target.is_queued_for_deletion())
	assert_false(bare.is_queued_for_deletion(),
		"null-data enemy left alone")

func test_despawn_is_safe_on_duplicate_call():
	# RemoteKillApplier's rising-edge gate normally prevents a duplicate
	# despawn, but a callsite that forgets the gate must not crash —
	# queue_free is idempotent.
	var e := _make_enemy_in_tree("r1_e0")
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	# Second call still finds the node (queue_free is deferred, node is
	# still in the group until end-of-frame) and re-queues — safe no-op.
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	assert_true(e.is_queued_for_deletion())

func test_despawn_ignores_non_enemy_node_in_enemies_group():
	# Defensive: if some other system add_to_group("enemies")'d a non-Enemy
	# node, the is Enemy check must skip it rather than crash on a cast.
	var stray := Node2D.new()
	stray.add_to_group("enemies")
	add_child_autofree(stray)
	var target := _make_enemy_in_tree("r1_e0")
	assert_true(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
	assert_true(target.is_queued_for_deletion())
	assert_false(stray.is_queued_for_deletion(),
		"non-Enemy node in group left alone")

func test_despawn_returns_false_when_only_non_enemy_in_group():
	# Cousin of the above: group contains stray nodes but no matching
	# Enemy. Must return false (no rising edge).
	var stray := Node2D.new()
	stray.add_to_group("enemies")
	add_child_autofree(stray)
	assert_false(RemoteEnemyDespawner.despawn(get_tree(), "r1_e0"))
