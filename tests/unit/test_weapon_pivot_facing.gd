extends GutTest

# Per-facing weapon mirroring (follow-up to PRD #223). The kitten's facing
# can change independently of swings (idle movement), so WeaponPivot needs
# an explicit set_facing() hook that mirrors the resting pose to the correct
# side without inverting the swing direction.
#
# Mirror mechanism: pivot.position.x and sprite.position.x flip by _facing,
# sprite.scale.x flips for pixel-mirroring, and all rotation values negate
# by _facing. The pivot itself keeps scale.x = 1 because Godot's transform
# applies scale before rotation — putting scale.x = -1 on the pivot would
# also invert the rotation's y-component and turn a downward chop into an
# upward chop. See test_weapon_pivot_facing_chop_direction for the
# behavior test that motivates this contract.

const _PIVOT_SCENE = preload("res://scenes/weapon_pivot.tscn")

func _make(def: WeaponDefinition) -> WeaponPivot:
	var p: WeaponPivot = _PIVOT_SCENE.instantiate()
	add_child_autofree(p)
	p.set_definition(def)
	return p

func test_set_facing_negative_mirrors_position_and_sprite_pixels() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.set_facing(-1.0)
	assert_eq(p.scale.x, 1.0,
		"pivot.scale.x stays at 1 — scale on the pivot would invert rotation y too")
	assert_eq(p.position.x, def.anchor_offset.x * -1.0,
		"pivot.position.x mirrors so the weapon rests on the left flank")
	var sprite := p.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.scale.x, def.sprite_scale.x * -1.0,
		"sprite pixels mirror via sprite.scale.x")
	assert_eq(sprite.position.x, def.weapon_offset.x * -1.0,
		"sprite.position.x mirrors so the grip stays on the pivot")

func test_set_facing_positive_restores_right_facing_pose() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.set_facing(-1.0)
	p.set_facing(1.0)
	assert_eq(p.position.x, def.anchor_offset.x)
	var sprite := p.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.scale.x, def.sprite_scale.x)
	assert_eq(sprite.position.x, def.weapon_offset.x)

func test_swing_left_negates_rotation_so_chop_reads_down() -> void:
	# Contract: swing(LEFT) mirrors the pose AND negates the rotation arc.
	# At the strike apex the local rotation reaches -(idle + swing_arc) so
	# that combined with the mirrored sprite position the blade tip lands
	# below the pivot. The "below pivot" geometry itself is pinned in
	# test_weapon_pivot_facing_chop_direction; this test pins the rotation
	# contract that produces it.
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.swing(Vector2.LEFT)
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var strike_rot: float = (def.idle_rotation + def.swing_arc) * -1.0
	assert_almost_eq(p.rotation, strike_rot, 0.05,
		"left-facing strike rotation is the negation of right-facing strike rotation")

func test_cast_left_mirrors_thrust_direction() -> void:
	# Thrust pushes the sprite forward along the kitten's facing. Facing
	# left → sprite.position.x should reach -thrust_distance (the wand
	# extends leftward from the paw), mirroring the right-facing apex of
	# +thrust_distance.
	var def := WeaponDefinition.wizard()
	var p := _make(def)
	p.cast(Vector2.LEFT)
	p.tick(def.windup_duration + def.strike_duration - 0.001)
	var sprite := p.get_node("Sprite2D") as Sprite2D
	assert_almost_eq(sprite.position.x, -def.thrust_distance, 0.5,
		"left-facing thrust extends sprite leftward, symmetric to right-facing")

func test_set_facing_zero_leaves_prior_facing_unchanged() -> void:
	# Stationary input (input_dir.x == 0) shouldn't snap the pivot back to
	# right-facing — the kitten keeps its last-known facing. Player.gd already
	# guards facing updates on input_dir != ZERO, but make the contract
	# explicit here so the pivot is safe to call unconditionally.
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.set_facing(-1.0)
	p.set_facing(0.0)
	assert_eq(p.position.x, def.anchor_offset.x * -1.0,
		"zero facing is a no-op, prior left-facing pose preserved")
