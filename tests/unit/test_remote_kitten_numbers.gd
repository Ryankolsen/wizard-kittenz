extends GutTest

# Tests for RemoteKitten.spawn_damage_number — the PRD #341 slice (issue
# #344) that paints a red floating damage number over a teammate's avatar
# when the existing OP_PLAYER_HIT packet arrives. No wire change: the
# damage amount is already on the wire; this is a rendering gap on the
# remote avatar.
#
# Mirrors test_remote_damage_visualizer's fixture style — build the node,
# add_child_autofree into get_tree(), then assert on the FloatingText
# spawned on the kitten's scene parent (FloatingText.spawn_at parents to
# parent so the label survives the kitten being freed).

func _make_kitten_in_tree(pid: String = "alice") -> RemoteKitten:
	var k := RemoteKitten.new()
	k.player_id = pid
	add_child_autofree(k)
	return k

func _find_floating_text_with_text(parent: Node, text: String) -> FloatingText:
	for child in parent.get_children():
		if child is FloatingText:
			var ft := child as FloatingText
			var label := ft.get_node_or_null("Label") as Label
			if label != null and label.text == text:
				return ft
	return null


func test_spawn_damage_number_spawns_floating_text_with_amount():
	var k := _make_kitten_in_tree()
	k.spawn_damage_number(7)
	var ft := _find_floating_text_with_text(k.get_parent(), "7")
	assert_not_null(ft, "FloatingText spawned on the kitten's scene parent")
	assert_eq(ft.get_node("Label").text, "7",
		"label text reflects the damage amount")


func test_spawn_damage_number_uses_physical_red():
	# The shared DamageKind PHYSICAL color — same value used by the local
	# melee floating-number path. Pulls from DamageKind.color_for so the
	# kind→color mapping stays single-source.
	var k := _make_kitten_in_tree()
	k.spawn_damage_number(4)
	var ft := _find_floating_text_with_text(k.get_parent(), "4")
	assert_not_null(ft)
	assert_eq(ft.get_node("Label").modulate,
		DamageKind.color_for(DamageKind.Kind.PHYSICAL),
		"teammate damage number uses PHYSICAL red")


func test_spawn_damage_number_zero_or_negative_spawns_nothing():
	# Matches the existing no-spurious-zero rule — the wire-side send guard
	# already drops non-positive damage, but the avatar method also gates
	# defensively so a malformed packet can't paint a "0" over a teammate.
	# Wrap in a dedicated parent so the scan scope is clean of FloatingTexts
	# spawned by sibling tests (autofree is deferred to the next idle frame).
	var parent := Node2D.new()
	add_child_autofree(parent)
	var k := RemoteKitten.new()
	k.player_id = "alice"
	parent.add_child(k)
	k.spawn_damage_number(0)
	k.spawn_damage_number(-3)
	for child in parent.get_children():
		assert_false(child is FloatingText,
			"no FloatingText spawned for non-positive damage")
