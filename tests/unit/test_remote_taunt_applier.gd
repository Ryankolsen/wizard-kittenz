extends GutTest

# Tests for RemoteTauntApplier — the inbound-from-wire counterpart to
# TauntBroadcaster. Sibling-shaped to RemoteEnemyDespawner: SceneTree
# group walk, idempotent guards, stamps EnemyData fields rather than
# mutating the scene tree.

func _make_enemy_in_tree(enemy_id: String) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e.data.enemy_id = enemy_id
	add_child_autofree(e)
	return e

func test_apply_returns_false_on_null_tree():
	# Test path / pre-scene-add: no tree to iterate.
	assert_false(RemoteTauntApplier.apply(null, "u1", "r3_e0", 2.0))

func test_apply_returns_false_on_empty_caster_id():
	# Without a cross-client identity the downstream lookup-by-id has
	# nothing to match against — reject at the seam rather than stamp
	# an unaddressable taunt.
	_make_enemy_in_tree("r3_e0")
	assert_false(RemoteTauntApplier.apply(get_tree(), "", "r3_e0", 2.0))

func test_apply_returns_false_on_empty_enemy_id():
	# Same shape as RemoteEnemyDespawner's guard — iterating with an
	# empty id would match every Enemy whose data.enemy_id defaults
	# to "" (legacy / test fixtures).
	assert_false(RemoteTauntApplier.apply(get_tree(), "u1", "", 2.0))

func test_apply_returns_false_on_non_positive_duration():
	# Mirrors TauntBroadcaster.on_taunt_applied's guard — zero/negative
	# duration is a cleared taunt, not a new one.
	_make_enemy_in_tree("r3_e0")
	assert_false(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 0.0))
	assert_false(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", -1.0))

func test_apply_returns_false_when_no_matching_enemy():
	# Already despawned by a prior packet OR never registered locally.
	_make_enemy_in_tree("r3_e0")
	assert_false(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e_missing", 2.0))

func test_apply_stamps_taunt_source_id_and_remaining():
	# Rising-edge contract: matching enemy gets caster_id stamped on
	# data.taunt_source_id and duration on data.taunt_remaining. The
	# AI lookup-by-id slice (next) reads taunt_source_id to find the
	# local Player node by Nakama id.
	var e := _make_enemy_in_tree("r3_e0")
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 2.0))
	assert_eq(e.data.taunt_source_id, "u1")
	assert_eq(e.data.taunt_remaining, 2.0)

func test_apply_does_not_set_taunt_target():
	# The receiving client doesn't have the caster's CharacterData
	# object — taunt_target stays null on this side. The AI's
	# cross-client redirect uses taunt_source_id, not taunt_target.
	var e := _make_enemy_in_tree("r3_e0")
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 2.0))
	assert_eq(e.data.taunt_target, null,
		"taunt_target unset on remote-applied taunt")

func test_apply_only_stamps_matching_id():
	# Multiple enemies in the tree; apply must surgically stamp only
	# the one matching enemy_id.
	var e1 := _make_enemy_in_tree("r3_e0")
	var e2 := _make_enemy_in_tree("r3_e1")
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 2.0))
	assert_eq(e1.data.taunt_source_id, "u1")
	assert_eq(e2.data.taunt_source_id, "",
		"non-matching enemy left untouched")
	assert_eq(e2.data.taunt_remaining, 0.0,
		"non-matching enemy timer untouched")

func test_apply_handles_enemy_with_null_data():
	# Pre-_setup_current_room Enemy node (data not yet assigned) is
	# in the "enemies" group but has no data. Defensive null-check
	# must skip it rather than crash on e.data.enemy_id.
	var bare := Enemy.new()
	bare.data = null
	add_child_autofree(bare)
	var target := _make_enemy_in_tree("r3_e0")
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 2.0))
	assert_eq(target.data.taunt_source_id, "u1")

func test_apply_ignores_non_enemy_node_in_enemies_group():
	# Defensive: another system add_to_group("enemies")'d a non-Enemy
	# node — the is Enemy check must skip it.
	var stray := Node2D.new()
	stray.add_to_group("enemies")
	add_child_autofree(stray)
	var target := _make_enemy_in_tree("r3_e0")
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 2.0))
	assert_eq(target.data.taunt_source_id, "u1")

func test_apply_overwrites_existing_taunt_remaining():
	# A re-cast (or duplicate packet) with a fresh duration replaces
	# the existing window — same shape as the local resolver's stamp
	# (which also overwrites). tick_taunt's decay is the only path
	# that lowers the value.
	var e := _make_enemy_in_tree("r3_e0")
	e.data.taunt_source_id = "u_other"
	e.data.taunt_remaining = 0.5
	assert_true(RemoteTauntApplier.apply(get_tree(), "u1", "r3_e0", 3.0))
	assert_eq(e.data.taunt_source_id, "u1")
	assert_eq(e.data.taunt_remaining, 3.0)
