extends GutTest

# Slice 2 of PRD #223 / issue #225. The wizard's PointLight2D blue pulse is
# driven by the choreographer's strike-phase entry rather than the
# attack-input frame. This test pins that timing: the pulse callback fires
# exactly once, and not until the strike phase begins.

var _strike_entries: int = 0
var _all_entries: Array = []

func before_each() -> void:
	_strike_entries = 0
	_all_entries = []

func _on_phase_entered(p: int) -> void:
	_all_entries.append(p)
	if p == AttackChoreographer.Phase.STRIKE:
		_strike_entries += 1

func test_pulse_callback_fires_once_at_strike_phase_entry() -> void:
	var c := AttackChoreographer.new()
	c.definition = WeaponDefinition.wizard()
	c.phase_entered.connect(_on_phase_entered)
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.CAST)
	# Pre-strike: WINDUP entered but pulse should not have fired yet.
	assert_eq(_strike_entries, 0, "pulse must not fire on attack-press")
	# Tick through windup — strike entry should fire pulse exactly once.
	c.tick(c.definition.windup_duration + 0.001)
	assert_eq(_strike_entries, 1, "pulse fires once at strike-phase entry")
	# Continue through strike + recovery — pulse should not refire.
	c.tick(c.definition.strike_duration + 0.001)
	c.tick(c.definition.recovery_duration + 0.001)
	assert_eq(_strike_entries, 1, "pulse does not refire after strike phase")

func test_strike_vfx_signal_fires_on_strike_for_cast_attacks() -> void:
	# The wizard hooks _on_strike_vfx → _play_spell_flash in player.gd to
	# trigger the PointLight2D pulse. This is the choreographer-level pin
	# that the signal fires for CAST attacks too (not only SWING).
	var c := AttackChoreographer.new()
	c.definition = WeaponDefinition.wizard()
	var vfx_dirs: Array = []
	c.strike_vfx_requested.connect(func(d: Vector2) -> void: vfx_dirs.append(d))
	c.start_attack(Vector2.RIGHT, WeaponDefinition.AttackType.CAST)
	assert_eq(vfx_dirs.size(), 0, "no VFX before strike phase")
	c.tick(c.definition.windup_duration + 0.001)
	assert_eq(vfx_dirs.size(), 1, "exactly one VFX request at strike entry")
	assert_eq(vfx_dirs[0], Vector2.RIGHT)
