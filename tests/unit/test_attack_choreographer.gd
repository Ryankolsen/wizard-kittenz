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
