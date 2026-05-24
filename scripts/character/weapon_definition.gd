class_name WeaponDefinition
extends Resource

# Per-class weapon data driving WeaponPivot animation + AttackChoreographer
# phase timings. All four kitten classes are wired in as of slice 3
# (PRD #223 / issue #226).

enum AttackType { SWING, THRUST, CAST }

@export var texture_path: String = ""
@export var attack_type: AttackType = AttackType.SWING
@export var swing_arc: float = 2.0
@export var anchor_offset: Vector2 = Vector2.ZERO
@export var weapon_offset: Vector2 = Vector2.ZERO
@export var windup_duration: float = 0.08
@export var strike_duration: float = 0.12
@export var recovery_duration: float = 0.15
@export var idle_rotation: float = 0.0
# Forward translation distance in pixels for THRUST/CAST attack types. Unused
# by SWING — its animation is rotation-based, not translation-based.
@export var thrust_distance: float = 0.0
# Per-weapon sprite scale. Native pixel art is authored at varying sizes
# (the mug is 47x48, swords/wands closer to 48x12), so scale lets each
# preset right-size its sprite without rescaling the source asset.
@export var sprite_scale: Vector2 = Vector2.ONE

func total_duration() -> float:
	return windup_duration + strike_duration + recovery_duration

# Shared rest-pose for SWING weapons whose sprite is a horizontal stick with
# the tip on the right end (battle sword, sleepy staff). Anchor at the waist
# (positive y is down in Godot 2D; kitten sprite is 48px tall centered at y=0),
# rotated 90° CCW from horizontal so the tip points UP, then tilted ~35° forward
# (CW from vertical) so the shaft clears the kitten's face instead of crossing
# it. The swing then arcs from up-behind through overhead to down-forward —
# a proper overhead chop.
const _OVERHEAD_CHOP_ANCHOR := Vector2(2, 10)
const _OVERHEAD_CHOP_IDLE_ROTATION := -PI / 2.0 + 0.6108652381980153  # -PI/2 + 35°

static func _apply_overhead_chop_pose(d: WeaponDefinition) -> void:
	d.attack_type = AttackType.SWING
	d.anchor_offset = _OVERHEAD_CHOP_ANCHOR
	d.idle_rotation = _OVERHEAD_CHOP_IDLE_ROTATION

# Battle kitten preset — sword in ~120° arc. weapon_offset (16, 0) puts the
# sprite's grip on the pivot so rotation happens around the hand, not the
# sword's geometric center.
static func battle() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	_apply_overhead_chop_pose(d)
	d.texture_path = "res://assets/sprites/weapon_sword_sprite.png"
	d.swing_arc = 2.1
	d.weapon_offset = Vector2(16, 0)
	d.windup_duration = 0.08
	d.strike_duration = 0.12
	d.recovery_duration = 0.15
	return d

# Wizard kitten preset — wand thrusts forward (CAST) rather than swinging in
# an arc. The strike apex translates the wand outward by thrust_distance
# along the facing direction; rotation stays at idle_rotation throughout.
# Held horizontally (idle_rotation 0) so the wand's tip leads on the thrust.
static func wizard() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.texture_path = "res://assets/sprites/weapon_wand_sprite.png"
	d.attack_type = AttackType.CAST
	d.swing_arc = 0.0
	d.anchor_offset = Vector2(2, 8)
	d.weapon_offset = Vector2.ZERO
	d.windup_duration = 0.08
	d.strike_duration = 0.12
	d.recovery_duration = 0.18
	d.idle_rotation = 0.0
	d.thrust_distance = 10.0
	return d

# Sleepy kitten preset — green staff in a SWING arc. Slightly slower windup +
# softer arc evoke the class's drowsy character without slowing the strike-
# window down to where it feels unresponsive. weapon_offset.x = 24 puts the
# BUTT exactly on the pivot — combined with the sprite's half-width, that
# keeps the butt glued to the grip through every rotation while the orb
# traces a 48px-radius arc around it. (Battle uses 16 instead of 24 because
# the sword is held mid-grip, not at the pommel.)
static func sleepy() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	_apply_overhead_chop_pose(d)
	d.texture_path = "res://assets/sprites/weapon_staff_sprite.png"
	d.swing_arc = 1.8
	d.weapon_offset = Vector2(24, 0)
	d.windup_duration = 0.1
	d.strike_duration = 0.12
	d.recovery_duration = 0.18
	return d

# Chonk kitten preset — mug-bash SWING. The mug sprite is 47x48 (tall, grip
# on the left edge) rather than the 48x12 horizontal-stick shape the other
# three weapons share, so weapon_offset shifts the child sprite to the right
# of the pivot. That puts the rotation origin at the mug's handle so it
# swings around the grip instead of its geometric center — without this
# the mug would pinwheel mid-air with the handle whipping past the paw.
static func chonk() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.texture_path = "res://assets/sprites/weapon_mug_sprite.png"
	d.attack_type = AttackType.SWING
	d.swing_arc = 2.3
	d.anchor_offset = Vector2(4, 2)
	d.weapon_offset = Vector2(10, 0)
	d.sprite_scale = Vector2(0.5, 0.5)
	d.windup_duration = 0.1
	d.strike_duration = 0.14
	d.recovery_duration = 0.18
	d.idle_rotation = 0.2
	return d

# Lookup hook for SpriteHelper / player.gd. All four kitten classes return a
# preset as of slice 3 — cat-tier and other classes still return null and
# fall through any caller's null-guard.
static func for_class(cc: int) -> WeaponDefinition:
	if cc == CharacterData.CharacterClass.BATTLE_KITTEN:
		return battle()
	if cc == CharacterData.CharacterClass.WIZARD_KITTEN:
		return wizard()
	if cc == CharacterData.CharacterClass.SLEEPY_KITTEN:
		return sleepy()
	if cc == CharacterData.CharacterClass.CHONK_KITTEN:
		return chonk()
	return null
