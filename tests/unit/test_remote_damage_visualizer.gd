extends GutTest

# Tests for RemoteDamageVisualizer — the scene-tree visual side of an
# OP_DAMAGE_DEALT packet (PRD #328 slice 6, issue #334). Mirrors
# test_remote_enemy_despawner.gd's structure since both walk the
# "enemies" group and match by enemy_id.
#
# The contract: spawn the same FloatingText overlay the solo damage
# path uses, parented to the enemy's scene parent (so it survives the
# enemy being freed the same frame — same shape as
# FloatingText.spawn_at).

func _make_enemy_in_tree(enemy_id: String, pos: Vector2 = Vector2.ZERO) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	e.data.enemy_id = enemy_id
	e.global_position = pos
	add_child_autofree(e)
	return e

func _find_floating_text(parent: Node) -> FloatingText:
	for child in parent.get_children():
		if child is FloatingText:
			return child as FloatingText
	return null

func test_spawn_returns_false_on_null_tree():
	assert_false(RemoteDamageVisualizer.spawn(null, "r1_e0", 5))

func test_spawn_returns_false_on_empty_enemy_id():
	# Defensive — without an id we can't route, and matching every
	# default-empty enemy_id would spawn a number above every enemy.
	assert_false(RemoteDamageVisualizer.spawn(get_tree(), "", 5))

func test_spawn_returns_false_on_non_positive_damage():
	# Send guard already drops a Miss / zero pulse, but the visualizer
	# also gates so a malformed packet from a future protocol drift
	# doesn't render a "0" label above the enemy.
	_make_enemy_in_tree("r1_e0")
	assert_false(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 0))
	assert_false(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", -3))

func test_spawn_returns_false_when_no_matching_enemy():
	# AC#6: missing enemy (already despawned on receiver) is a silent
	# no-op — false return, no FloatingText anywhere.
	_make_enemy_in_tree("r1_e0")
	assert_false(RemoteDamageVisualizer.spawn(get_tree(), "r1_e_does_not_exist", 7))

func test_spawn_returns_true_and_spawns_floating_text_at_enemy_position():
	# AC: the same FloatingText scene/component solo uses appears at the
	# enemy's world position with the broadcast damage value.
	var e := _make_enemy_in_tree("r1_e0", Vector2(123, 456))
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 12))
	# FloatingText.spawn_at parents to target's parent so the label
	# survives target queue_free — the visualizer follows the same shape.
	var ft := _find_floating_text(e.get_parent())
	assert_not_null(ft, "FloatingText spawned on the enemy's scene parent")
	assert_eq(ft.global_position, Vector2(123, 456),
		"floating text positioned at the enemy's world position")
	assert_eq(ft.get_node("Label").text, "12",
		"text reflects the broadcast damage value")

func test_spawn_only_matches_target_enemy():
	# Multiple enemies in the tree; only the matching enemy_id gets a
	# floating number.
	var e1 := _make_enemy_in_tree("r1_e0", Vector2(10, 10))
	var e2 := _make_enemy_in_tree("r2_e0", Vector2(50, 50))
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 7))
	assert_not_null(_find_floating_text(e1.get_parent()),
		"matching enemy spawned floating text on its scene parent")
	# Both enemies share the same scene parent (self/test) — guard against a
	# false positive by walking e2's children only (where spawn() would
	# never write, but verifying nothing leaked).
	for child in e2.get_children():
		assert_false(child is FloatingText,
			"non-target enemy got no child FloatingText")

func test_spawn_handles_enemy_with_null_data():
	# Pre-_setup_current_room Enemy in the group has no enemy_id. Defensive
	# skip rather than crash on e.data.enemy_id.
	var bare := Enemy.new()
	bare.data = null
	add_child_autofree(bare)
	var target := _make_enemy_in_tree("r1_e0")
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 9))
	assert_not_null(_find_floating_text(target.get_parent()))

func _find_floating_text_with_text(parent: Node, text: String) -> FloatingText:
	# Disambiguates between FloatingTexts spawned across sibling tests:
	# autofree's queue_free is deferred to the next idle frame, so a
	# label spawned by an earlier test in the same group can still be
	# parented under the shared test root when the next test runs.
	# Matching by the damage value (unique per test below) pins us to
	# the FloatingText this test just spawned.
	for child in parent.get_children():
		if child is FloatingText:
			var ft := child as FloatingText
			var label := ft.get_node_or_null("Label") as Label
			if label != null and label.text == text:
				return ft
	return null


func test_spawn_colors_physical_red():
	# #346: physical damage paints the FloatingText with the shared
	# DamageKind PHYSICAL color — same value the local melee path uses.
	var e := _make_enemy_in_tree("r1_e0", Vector2(10, 10))
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 5, DamageKind.Kind.PHYSICAL))
	var ft := _find_floating_text_with_text(e.get_parent(), "5")
	assert_not_null(ft)
	assert_eq(ft.get_node("Label").modulate, DamageKind.color_for(DamageKind.Kind.PHYSICAL),
		"physical kind renders in the shared PHYSICAL color")


func test_spawn_colors_magic_blue():
	# #346: magic damage paints the FloatingText with the shared
	# DamageKind MAGIC color so a teammate's spell shows blue on every
	# peer's screen, matching the local wizard cast / spell-resolver
	# spawn paths from #343.
	var e := _make_enemy_in_tree("r1_e0", Vector2(20, 20))
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 8, DamageKind.Kind.MAGIC))
	var ft := _find_floating_text_with_text(e.get_parent(), "8")
	assert_not_null(ft)
	assert_eq(ft.get_node("Label").modulate, DamageKind.color_for(DamageKind.Kind.MAGIC),
		"magic kind renders in the shared MAGIC color")


func test_spawn_unknown_kind_falls_back_to_physical():
	# Forward-version peer on the wire (a future kind a pre-this-build
	# receiver doesn't know): DamageKind.color_for folds to PHYSICAL so
	# the label is never blank.
	var e := _make_enemy_in_tree("r1_e0", Vector2(30, 30))
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 3, 999))
	var ft := _find_floating_text_with_text(e.get_parent(), "3")
	assert_not_null(ft)
	assert_eq(ft.get_node("Label").modulate, DamageKind.color_for(DamageKind.Kind.PHYSICAL),
		"unknown kind falls back to PHYSICAL color")


func test_spawn_ignores_non_enemy_node_in_enemies_group():
	# Defensive — non-Enemy in the group must not crash on the cast.
	var stray := Node2D.new()
	stray.add_to_group("enemies")
	add_child_autofree(stray)
	var target := _make_enemy_in_tree("r1_e0")
	assert_true(RemoteDamageVisualizer.spawn(get_tree(), "r1_e0", 4))
	assert_not_null(_find_floating_text(target.get_parent()))
