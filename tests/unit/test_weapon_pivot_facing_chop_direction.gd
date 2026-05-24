extends GutTest

# Follow-up to the per-facing weapon mirroring: the previous implementation
# put scale.x = -1 on the WeaponPivot, but Godot's transform applies scale
# BEFORE rotation — so the rotation's y-component got inverted too. Visually
# the strike apex ended up ABOVE the pivot when facing left ("swinging up").
#
# Contract pinned here: regardless of facing, the blade tip's parent-frame
# y at the strike apex is below the pivot's parent-frame y. The math is
# done via Transform2D so it catches any future regression where scale
# accidentally re-applies to the pivot (rather than to the sprite alone).

const _PIVOT_SCENE = preload("res://scenes/weapon_pivot.tscn")

func _make(def: WeaponDefinition) -> WeaponPivot:
	var p: WeaponPivot = _PIVOT_SCENE.instantiate()
	add_child_autofree(p)
	p.set_definition(def)
	return p

# Blade tip in the pivot's PARENT frame (i.e., player frame). Compose
# sprite.transform (its local position/scale) with pivot.transform (its
# position/rotation/scale) so any scaling on either node is faithfully
# reflected — that's the exact behavior we want to assert.
func _blade_tip_in_parent_frame(p: WeaponPivot, half_width: float) -> Vector2:
	var sprite := p.get_node("Sprite2D") as Sprite2D
	var tip_local := Vector2(half_width, 0)
	var tip_in_pivot: Vector2 = sprite.transform * tip_local
	return p.transform * tip_in_pivot

func test_swing_right_blade_tip_below_pivot_at_mid_strike() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.swing(Vector2.RIGHT)
	p.tick(def.windup_duration + def.strike_duration * 0.5)
	var tip := _blade_tip_in_parent_frame(p, 24.0)
	assert_gt(tip.y, p.position.y,
		"right-facing tip should be below pivot at mid-strike (sanity)")

func test_swing_left_blade_tip_below_pivot_at_mid_strike() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.swing(Vector2.LEFT)
	p.tick(def.windup_duration + def.strike_duration * 0.5)
	var tip := _blade_tip_in_parent_frame(p, 24.0)
	assert_gt(tip.y, p.position.y,
		"left-facing tip must also chop DOWN — the regression that motivated this test had tip.y < pivot.y here")

# Wand cast: at strike apex the wand tip extends OUTWARD from the kitten
# in the facing direction, not back across the body. The thrust offset is
# multiplied by _facing so positive thrust always points forward.
func test_cast_left_wand_tip_extends_leftward_at_strike_apex() -> void:
	var def := WeaponDefinition.wizard()
	var p := _make(def)
	p.cast(Vector2.LEFT)
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var tip := _blade_tip_in_parent_frame(p, 24.0)
	# Wand should extend leftward → tip.x is well to the left of the pivot.
	# Use a margin smaller than the wand's own length so this doesn't break
	# on small thrust_distance tweaks.
	assert_lt(tip.x, p.position.x - 10.0,
		"left-facing wand tip extends leftward of pivot at strike apex")

func test_cast_right_wand_tip_extends_rightward_at_strike_apex() -> void:
	var def := WeaponDefinition.wizard()
	var p := _make(def)
	p.cast(Vector2.RIGHT)
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var tip := _blade_tip_in_parent_frame(p, 24.0)
	assert_gt(tip.x, p.position.x + 10.0,
		"right-facing wand tip extends rightward of pivot at strike apex (sanity mirror)")
