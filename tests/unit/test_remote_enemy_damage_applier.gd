extends GutTest

# Tests for RemoteEnemyDamageApplier — the data-side helper that applies
# an OP_DAMAGE_DEALT delta to the matching local Enemy.data.hp on remote
# peers so the polled enemy/boss bar drops in lockstep with the floating
# number (PRD #341, issue #342).
#
# Mirrors test_remote_damage_visualizer.gd's fixture (Enemy +
# EnemyData.make_new + add_child_autofree). Despawn is intentionally
# NOT this helper's job — the kill packet drives that — so test #3
# asserts the enemy survives a hit that drives HP to the floor.

func _make_enemy_in_tree(enemy_id: String, starting_hp: int = 8) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	e.data.enemy_id = enemy_id
	e.data.hp = starting_hp
	add_child_autofree(e)
	return e

func test_apply_decrements_hp_on_matching_enemy():
	var e := _make_enemy_in_tree("r1_e0", 8)
	assert_true(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 3))
	assert_eq(e.data.hp, 5, "matching enemy hp decremented by damage amount")

func test_apply_clamps_hp_at_zero():
	var e := _make_enemy_in_tree("r1_e0", 2)
	assert_true(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 5))
	assert_eq(e.data.hp, 0, "hp clamped to zero — never negative")

func test_apply_does_not_queue_free_on_zero_hp():
	# AC#4 — despawn is OP_KILL's job; this helper's HP-to-floor must
	# leave the node in the tree so a dropped kill packet doesn't ghost.
	var e := _make_enemy_in_tree("r1_e0", 1)
	assert_true(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 1))
	assert_eq(e.data.hp, 0)
	assert_false(e.is_queued_for_deletion(),
		"enemy is not despawned by hp reaching the floor — kill packet owns removal")

func test_apply_returns_false_when_no_matching_enemy():
	_make_enemy_in_tree("r1_e0", 8)
	assert_false(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e_does_not_exist", 3))

func test_apply_returns_false_on_null_tree():
	assert_false(RemoteEnemyDamageApplier.apply(null, "r1_e0", 3))

func test_apply_returns_false_on_empty_enemy_id():
	var e := _make_enemy_in_tree("r1_e0", 8)
	assert_false(RemoteEnemyDamageApplier.apply(get_tree(), "", 3))
	assert_eq(e.data.hp, 8, "hp unchanged when enemy_id is empty")

func test_apply_returns_false_on_non_positive_damage():
	var e := _make_enemy_in_tree("r1_e0", 8)
	assert_false(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 0))
	assert_false(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", -3))
	assert_eq(e.data.hp, 8, "hp unchanged on non-positive damage")

func test_apply_only_decrements_target_enemy():
	var e1 := _make_enemy_in_tree("r1_e0", 8)
	var e2 := _make_enemy_in_tree("r2_e0", 8)
	assert_true(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 3))
	assert_eq(e1.data.hp, 5)
	assert_eq(e2.data.hp, 8, "non-target enemy hp untouched")

func test_apply_handles_enemy_with_null_data():
	# Pre-_setup_current_room Enemy in the group has no data. Defensive
	# skip rather than crash on e.data.enemy_id.
	var bare := Enemy.new()
	bare.data = null
	add_child_autofree(bare)
	var target := _make_enemy_in_tree("r1_e0", 8)
	assert_true(RemoteEnemyDamageApplier.apply(get_tree(), "r1_e0", 4))
	assert_eq(target.data.hp, 4)
