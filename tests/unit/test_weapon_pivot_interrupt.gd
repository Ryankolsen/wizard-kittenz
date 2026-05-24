extends GutTest

# Slice 5 of PRD #223 / issue #228. WeaponPivot.interrupt() must reset to
# the idle pose under all entry conditions — mid-swing, mid-thrust, and
# (defensively) when called before any swing has started.

const _PIVOT_SCENE = preload("res://scenes/weapon_pivot.tscn")

func _make(def: WeaponDefinition) -> WeaponPivot:
	var p: WeaponPivot = _PIVOT_SCENE.instantiate()
	add_child_autofree(p)
	p.set_definition(def)
	return p

func test_interrupt_mid_swing_resets_to_idle_rotation() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	p.swing(Vector2.RIGHT)
	# Advance through windup into the strike phase so rotation has visibly
	# diverged from idle_rotation before the interrupt.
	p.tick(def.windup_duration + def.strike_duration * 0.5)
	assert_ne(p.rotation, def.idle_rotation,
		"sanity: pivot should have rotated away from idle before interrupt")
	p.interrupt()
	assert_almost_eq(p.rotation, def.idle_rotation, 0.0001,
		"interrupt snaps rotation back to idle_rotation")
	assert_eq(p.phase, WeaponPivot.Phase.IDLE)

func test_interrupt_mid_thrust_resets_sprite_to_rest_offset() -> void:
	var def := WeaponDefinition.wizard()
	var p := _make(def)
	p.cast(Vector2.RIGHT)
	# Advance into the strike phase so the sprite has thrust forward.
	p.tick(def.windup_duration + def.strike_duration * 0.5)
	var sprite := p.get_node("Sprite2D") as Sprite2D
	assert_ne(sprite.position.x, def.weapon_offset.x,
		"sanity: sprite should have translated forward before interrupt")
	p.interrupt()
	assert_almost_eq(sprite.position.x, def.weapon_offset.x, 0.0001,
		"interrupt restores sprite to rest weapon_offset")
	assert_eq(p.phase, WeaponPivot.Phase.IDLE)

# Edge case from issue #228 test plan: interrupting before any swing must
# be a no-op (no errors, no rotation change). Guards against future refactors
# that assume an active phase in interrupt().
func test_interrupt_before_any_swing_is_a_noop() -> void:
	var def := WeaponDefinition.battle()
	var p := _make(def)
	var before_rot := p.rotation
	p.interrupt()
	assert_almost_eq(p.rotation, before_rot, 0.0001,
		"interrupt without a prior swing leaves rotation unchanged")
	assert_eq(p.phase, WeaponPivot.Phase.IDLE)
