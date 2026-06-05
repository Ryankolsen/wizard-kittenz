extends GutTest

# Issue #343 (PRD #341 — Typed damage points): the magic/spell damage path
# in SpellEffectResolver previously resolved damage but spawned no floating
# number. This tests the closed gap: a DAMAGE-kind spell hitting an Enemy
# node spawns a blue (magic) FloatingText over the target. Mirrors the
# in-tree enemy fixture from test_remote_damage_visualizer.gd so the spawn
# point is exercised end-to-end against a real scene node.
#
# Each test uses a fresh wrapper Node2D parent so FloatingText spawns
# (parented to the enemy's scene parent, not the enemy itself, since
# FloatingText.spawn_at must survive a same-frame enemy queue_free) are
# isolated per test and torn down via add_child_autofree.

func _wrapper() -> Node2D:
	var w := Node2D.new()
	add_child_autofree(w)
	return w

func _make_enemy_under(wrapper: Node2D, pos: Vector2 = Vector2.ZERO) -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	e.global_position = pos
	wrapper.add_child(e)
	return e

func _floating_texts_under(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is FloatingText:
			out.append(child)
	return out

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)

func test_damage_spell_spawns_blue_floating_text_over_enemy_node():
	var wrapper := _wrapper()
	var enemy := _make_enemy_under(wrapper, Vector2(50, 70))
	var spell := Spell.make("s", "Spark", Spell.EffectKind.DAMAGE, 4, 1.0)
	var dealt := SpellEffectResolver.apply(spell, _caster(), [enemy])
	assert_gt(dealt, 0, "spell deals positive damage to the enemy")
	var fts := _floating_texts_under(wrapper)
	assert_eq(fts.size(), 1, "exactly one FloatingText spawned")
	var ft: FloatingText = fts[0]
	assert_eq(ft.global_position, Vector2(50, 70),
		"floating text positioned at the enemy's world position")
	assert_eq(ft.get_node("Label").modulate, DamageKind.color_for(DamageKind.Kind.MAGIC),
		"label colored with magic (blue) per kind→color mapping")
	assert_eq(ft.get_node("Label").text, str(dealt),
		"text reflects damage dealt")

func test_area_spell_spawns_blue_floating_text_on_each_hit_enemy():
	var wrapper := _wrapper()
	var e1 := _make_enemy_under(wrapper, Vector2(10, 10))
	var e2 := _make_enemy_under(wrapper, Vector2(40, 40))
	var spell := Spell.make("n", "Nova", Spell.EffectKind.AREA, 5, 1.0)
	SpellEffectResolver.apply(spell, _caster(), [e1, e2])
	assert_eq(_floating_texts_under(wrapper).size(), 2,
		"one floating number per damaged enemy in AOE")

func test_zero_damage_spawns_no_floating_text():
	# A dead-on-arrival target is_alive() returns false; the resolver skips
	# the take_damage call entirely, so no number should appear (matches the
	# existing no-spurious-0 rule from PRD #85).
	var wrapper := _wrapper()
	var enemy := _make_enemy_under(wrapper)
	enemy.data.hp = 0
	var spell := Spell.make("s", "Spark", Spell.EffectKind.DAMAGE, 4, 1.0)
	var dealt := SpellEffectResolver.apply(spell, _caster(), [enemy])
	assert_eq(dealt, 0, "dead target absorbs no damage")
	assert_eq(_floating_texts_under(wrapper).size(), 0,
		"no FloatingText spawned when no damage was dealt")

func test_data_only_target_does_not_crash_and_spawns_no_floating_text():
	# Backwards compat with existing call sites that pass EnemyData (no
	# scene node): the resolver still applies damage but has no node to
	# attach a label to. The wrapper stays empty of FloatingText.
	var wrapper := _wrapper()
	var enemy_data := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("s", "Spark", Spell.EffectKind.DAMAGE, 3, 1.0)
	var dealt := SpellEffectResolver.apply(spell, _caster(), [enemy_data])
	assert_gt(dealt, 0)
	assert_eq(_floating_texts_under(wrapper).size(), 0,
		"data-only target path does not leak a FloatingText into the tree")
