extends GutTest

# Per-facing weapon mirroring (follow-up to PRD #223). The kitten's facing
# can change independently of swings (idle movement), so WeaponPivot needs
# an explicit set_facing() hook that mirrors the entire pivot — position,
# sprite, and rotation — via scale.x = ±1. The arc/thrust math then stays
# positive in local space; the parent scale handles the visual flip.

const _PIVOT_SCENE = preload("res://scenes/weapon_pivot.tscn")

func _make(def: WeaponDefinition) -> WeaponPivot:
	var p: WeaponPivot = _PIVOT_SCENE.instantiate()
	add_child_autofree(p)
	p.set_definition(def)
	return p

func test_set_facing_negative_flips_scale_x() -> void:
	var p := _make(WeaponDefinition.battle())
	p.set_facing(-1.0)
	assert_eq(p.scale.x, -1.0, "left facing mirrors the pivot via scale.x = -1")

func test_set_facing_positive_restores_scale_x() -> void:
	var p := _make(WeaponDefinition.battle())
	p.set_facing(-1.0)
	p.set_facing(1.0)
	assert_eq(p.scale.x, 1.0, "right facing restores scale.x to 1")

func test_swing_left_flips_scale_and_keeps_local_arc_positive() -> void:
	# Contract: visual flip is owned by scale.x, not by arc-sign negation in
	# swing math. After swing(LEFT), pivot.scale.x is -1 AND local rotation
	# walks from idle to (idle + swing_arc) — positive in local space —
	# while the parent scale makes it appear as a left-side arc visually.
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.swing(Vector2.LEFT)
	assert_eq(p.scale.x, -1.0, "swing(LEFT) flips the pivot")
	# Advance just into the strike phase so rotation reaches strike target.
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var strike_rot: float = def.idle_rotation + def.swing_arc
	assert_almost_eq(p.rotation, strike_rot, 0.05,
		"local rotation walks the positive arc; scale handles the visual flip")

func test_cast_left_flips_scale_and_keeps_local_thrust_positive() -> void:
	var def := WeaponDefinition.wizard()
	var p := _make(def)
	p.cast(Vector2.LEFT)
	assert_eq(p.scale.x, -1.0, "cast(LEFT) flips the pivot")
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var sprite := p.get_node("Sprite2D") as Sprite2D
	assert_almost_eq(sprite.position.x, def.thrust_distance, 0.5,
		"local thrust stays positive; scale handles the visual flip")

func test_set_facing_zero_leaves_prior_facing_unchanged() -> void:
	# Stationary input (input_dir.x == 0) shouldn't snap the pivot back to
	# right-facing — the kitten keeps its last-known facing. Player.gd already
	# guards facing updates on input_dir != ZERO, but make the contract
	# explicit here so the pivot is safe to call unconditionally.
	var p := _make(WeaponDefinition.battle())
	p.set_facing(-1.0)
	p.set_facing(0.0)
	assert_eq(p.scale.x, -1.0, "zero facing is a no-op, prior facing preserved")
