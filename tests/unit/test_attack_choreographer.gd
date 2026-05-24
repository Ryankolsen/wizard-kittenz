extends GutTest

# Slice 1 of PRD #223 / issue #224. AttackChoreographer drives the
# windup → strike → recovery state machine and emits boundary signals so
# callers can gate hitbox + VFX without coupling that into the choreographer.

var _phases: Array = []
var _hitbox_log: Array = []
var _vfx_dirs: Array = []

func before_each() -> void:
	_phases = []
	_hitbox_log = []
	_vfx_dirs = []

func _make() -> AttackChoreographer:
	var c := AttackChoreographer.new()
	c.definition = WeaponDefinition.battle()
	c.phase_entered.connect(func(p: int) -> void: _phases.append(p))
	c.hitbox_enable_requested.connect(func() -> void: _hitbox_log.append("on"))
	c.hitbox_disable_requested.connect(func() -> void: _hitbox_log.append("off"))
	c.strike_vfx_requested.connect(func(d: Vector2) -> void: _vfx_dirs.append(d))
	return c

# Test 2 from issue #224 — phases fire in order.
func test_phases_fire_in_order_windup_strike_recovery() -> void:
	var c := _make()
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.SWING)
	# Cover all three phase durations.
	var def := c.definition
	c.tick(def.windup_duration + 0.001)
	c.tick(def.strike_duration + 0.001)
	c.tick(def.recovery_duration + 0.001)
	# Expect: WINDUP entered on start, STRIKE entered after windup_duration,
	# RECOVERY after strike_duration, IDLE after recovery_duration.
	assert_eq(_phases, [
		AttackChoreographer.Phase.WINDUP,
		AttackChoreographer.Phase.STRIKE,
		AttackChoreographer.Phase.RECOVERY,
		AttackChoreographer.Phase.IDLE,
	])

# Test 3 from issue #224 — hitbox enable bound to strike phase. The window
# between hitbox-on and hitbox-off equals WeaponDefinition.strike_duration
# (because both events are gated on strike-phase entry/exit, not on a
# separate timer).
func test_hitbox_enable_disable_brackets_strike_phase() -> void:
	var c := _make()
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.SWING)
	var def := c.definition
	# Tick through windup — hitbox should turn on at the windup→strike edge.
	c.tick(def.windup_duration + 0.001)
	assert_eq(_hitbox_log, ["on"])
	# Tick through strike — hitbox should turn off at the strike→recovery edge.
	c.tick(def.strike_duration + 0.001)
	assert_eq(_hitbox_log, ["on", "off"])

# Strike VFX request carries the attack direction (PRD: slash effect fires
# at strike, oriented by facing).
func test_strike_vfx_requested_with_attack_direction() -> void:
	var c := _make()
	c.start_attack(Vector2.LEFT, WeaponDefinition.AttackType.SWING)
	c.tick(c.definition.windup_duration + 0.001)
	assert_eq(_vfx_dirs.size(), 1)
	assert_eq(_vfx_dirs[0], Vector2.LEFT)

# Slice 2 (issue #225) test 1: CAST attack type drives forward thrust
# (sprite translation) rather than rotation. Pivot rotation stays at idle
# throughout; the child Sprite2D's position.x reaches the thrust offset at
# strike-phase peak.
func test_cast_attack_thrusts_forward_without_rotation() -> void:
	var pivot_scene = preload("res://scenes/weapon_pivot.tscn")
	var pivot: WeaponPivot = pivot_scene.instantiate()
	add_child_autofree(pivot)
	var def := WeaponDefinition.wizard()
	pivot.set_definition(def)
	var c := AttackChoreographer.new()
	c.definition = def
	c.weapon_pivot = pivot
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.CAST)
	var idle_rot := pivot.rotation
	c.tick(def.windup_duration + 0.001)
	# At strike-phase entry, advance to strike-phase end so the sprite reaches
	# the full thrust offset.
	c.tick(def.strike_duration - 0.001)
	var sprite := pivot.get_node("Sprite2D") as Sprite2D
	assert_almost_eq(sprite.position.x, def.thrust_distance, 0.5,
		"sprite thrusts forward by thrust_distance at strike apex")
	assert_almost_eq(pivot.rotation, idle_rot, 0.001,
		"pivot rotation unchanged during CAST")

# Slice 3 (issue #226): every kitten class has a WeaponDefinition so the
# choreographer phase callbacks fire for all four — no class falls back to
# the legacy _play_attack_flash shake (which has been removed). This pins
# that for_class returns a usable definition for each kitten and that
# start_attack drives the phase machine into STRIKE.
func test_all_kitten_classes_route_through_choreographer_phase_machine() -> void:
	var kitten_classes := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for cc in kitten_classes:
		var def := WeaponDefinition.for_class(cc)
		assert_not_null(def, "for_class returns a definition for class %s" % cc)
		var phases_seen: Array = []
		var c := AttackChoreographer.new()
		c.definition = def
		c.phase_entered.connect(func(p: int) -> void: phases_seen.append(p))
		c.start_attack(Vector2.RIGHT, def.attack_type)
		c.tick(def.windup_duration + 0.001)
		assert_true(phases_seen.has(AttackChoreographer.Phase.STRIKE),
			"class %s reaches STRIKE via the choreographer" % cc)

# Interrupt mid-strike disables the hitbox so a re-attacked player can't
# stick the hitbox open by spamming attacks.
func test_interrupt_mid_strike_disables_hitbox() -> void:
	var c := _make()
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.SWING)
	c.tick(c.definition.windup_duration + 0.001)
	assert_eq(_hitbox_log, ["on"])
	c.interrupt()
	assert_eq(_hitbox_log, ["on", "off"])
	assert_eq(c.phase, AttackChoreographer.Phase.IDLE)
